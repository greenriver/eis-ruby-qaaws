require 'savon'
require 'wasabi'
require 'active_support'
require 'active_support/core_ext'
require 'date'
require 'json'

require_relative 'string_type_checks'

class Qaaws
  class QaawsError < StandardError
  end

  def initialize(options={})
    @username = options[:username]
    @password = options[:password]
    @serialized_session = options[:serialized_session]
    
    unless ((@username and @password) or (@serialized_session))
      raise QaawsError, 'Must provide username and password, or serialized_session to create a Qaaws Object' 
    end

    @endpoint = options[:endpoint]
    @cuid = options[:cuid]
    @httpi_opts = options[:httpi_opts] || {}
    @wsdl_location = "#{@endpoint}?wsdl=1&cuid=#{@cuid}"

    puts "WSDL Location: " + @wsdl_location
  end

  def request(options={})
    soap_header = nil
    request_type = get_request_type(options)
    request_name = get_request_name(options, request_type)
    response_name = get_response_name(options, request_type)
    message = {}
    message = prepare_options(options, request_type, request_name) unless request_type == 'lov'

    if @username and @password
      message.merge!(login: @username, password: @password) 
    else
      #Need to supply this as a string as exit-Savon doesn't currently support conversion of hashes to CDATA block
      soap_header = "<QaaWSHeader><serializedSession><![CDATA[#{@serialized_session}]]></serializedSession></QaaWSHeader>"
    end

    #Store this in order to log xml request
    ops = savon_client.operation(request_name.to_sym)      
    request_xml_string = ops.build(message: message).to_s

    puts "SOAP Request:"
    puts request_xml_string

    puts "Message: "
    puts message

    resp = savon_client.call(request_name.to_sym, message: message, soap_header: soap_header)

    puts "SOAP Response:"
    puts resp.to_s

    begin
      tbl = resp_to_table(resp, request_type, response_name) #response is structured differently depending on request type
    rescue
      message = resp.hash[:envelope][:body][response_name.to_sym][:message]
      if message
        raise QaawsError, resp.hash[:envelope][:body][response_name.to_sym][:message]
      else
        raise QaawsError, "Unable to convert XML to JSON"
      end
    end

    Qaaws::Table.new(tbl)
  end

  #This method sets the request type, which determines which SOAP action will be used
  def get_request_type(options)
      if options.key?(:lov) #If API consumer passes 'lov' param, set the request type as lov. The lov SOAP action will be used.
        return 'lov'
      elsif options.key?(:soap_action) #If API consumer passes 'soap_action' param, set the request type to 'custom_soap_action'.  The user's SOAP action will be used
        return 'custom_soap_action'
      else
        return 'run_qaas' #If API consumer does not pass 'lov' or 'soap_action', default the request type to 'run_qaaws', which uses the run_query_as_a_service SOAP action
      end
  end

  #This method sets the SOAP action
  def get_request_name(options, request_type)
    if request_type == 'lov'
      return 'values_of_' + options[:lov]
    elsif request_type == 'custom_soap_action'
      return options[:soap_action]
    else
      return 'run_query_as_a_service'
    end
  end

  #This method gets the response name, which is needed for the XML to JSON conversion
  def get_response_name(options, request_type)
    if request_type == 'lov'
      return 'values_of_' + options[:lov] + '_response'
    elsif request_type == 'custom_soap_action'
      return  options[:soap_action] + '_response'
    else 
      return 'run_query_as_a_service_response'
    end
  end

  #This method converts the XML response to a JSON response
  def resp_to_table(resp, request_type, response_name)
    if request_type == 'lov'
      resp_body = resp.hash[:envelope][:body][response_name.to_sym]
      return resp_body[:lov][:valueindex]
    
    elsif request_type == 'custom_soap_action'
      resp_body = resp.hash[:envelope][:body][response_name.to_sym]

      header_row = resp_body[:headers][:row]
      if header_row.kind_of?(Array) #if nested headers
        headers = header_row[header_row.length-1][:cell] #use deepest set of headers.  This should correspond to the JSON keys
      elsif header_row[:cell].kind_of?(Array)
          headers = header_row[:cell]
      else #If only one header, value is returned as string.  Need to convert this to an array
        headers = [header_row[:cell]]
      end
      
      rows = resp_body[:table][:row]
      
      if rows.kind_of?(Hash) #If rows are a hash, convert to array
        rows = rows[:cell]
      end

      tbl = []

      rows.each { |row| #convert XML to JSON array
          obj = {}
          row.kind_of?(Hash) ? cell = row[:cell] : cell = row
          if cell.kind_of?(Array) #Cell is an array becuase it has multiple records representing multiple keys in the JSON
            cell.each_with_index {|d, i| 
                if d.kind_of?(Hash) #Empty cells come through as a hash.  Convert to nil.
                  d = nil
                end
                obj[headers[i].to_sym] = d
            }
          else #Cell is a string becuase it has only one record, meaning there is only one JSON key.
            obj[headers[0].to_sym] = cell
          end

          tbl.push(obj)
      }

      return tbl

    else #run_query_as_a_service response
      resp_body = resp.hash[:envelope][:body][:run_query_as_a_service_response]
      raise QaawsError, "Qaaws Error: #{resp_body[:message]}" unless resp_body[:table]
      return ( resp_body[:table][:row].class == Hash ?  [ resp_body[:table][:row] ] : resp_body[:table][:row] )   #If we get only one row back then the XML translation makes this a Hash.  But we always want an Array.
    end
  end

  private
  def savon_client
    @savon_client ||= Savon.client(@httpi_opts.merge(wsdl: @wsdl_location).merge(convert_request_keys_to: :none))
  end

  def wsdl_obj
    #Right now doesn't seem that Savon exposes this Wasabi document (Ruby object for handling WSDL) over its public interface, so we instead create one ourselves
    doc = Wasabi::Document.new
    doc.document = @wsdl_location
    doc.request = Savon::WSDLRequest.new(@httpi_opts).build
    doc
  end

  def prepare_options(options, request_type, request_name)
    if request_type == 'custom_soap_action' #if request_type param is not actually sent via soap but only exists to indicate the method to use
      options.tap { |o| o.delete(request_type.to_sym) } #remove it 
    end

    clean_opts = {}
    spec_params = nil

    begin
      spec_params = wsdl_obj.operation_input_parameters(request_name.to_sym)
      if spec_params == nil
        raise QaawsError, "SOAP action #{request_name} not found.  Set the soap_action parameter equal to one of these: #{wsdl_obj.soap_actions.join(', ')}"
      end
    rescue NoMethodError
      raise QaawsError, "QaawsError: Cuid #{@cuid} is invalid, or WSDL not present at #{@wsdl_location}"
    end

    options.each do |k,v|
      if k.to_s == 'soap_action' then
        next
      end

      new_v = nil
      unless spec_params[k]
        raise QaawsError, "QaawsError: No parameter named '#{k}' found in service definition.  All params in service definition are: #{spec_params.keys.join(', ')}" 
      end
      if spec_params[k][:type] == 'dateTime'
        dt = (v.respond_to?(:parses_datetime?) and v.parses_datetime?) ? DateTime.parse(v) : v
        if dt.respond_to?(:strftime)
          new_v = dt.strftime("%m/%d/%Y %H:%M:%S")  #Qaaws wants its dates formatted this way to work properly
        else
          raise QaawsError, "Qaaws Error: Parameter #{k} is supposed to be a dateTime but value provided, #{v}, is not parseable as a Date or DateTime"
        end
      elsif request_type == 'custom_soap_action' and spec_params[k][:type]=='LovValueIndex' #webi reports require LOV to be formatted like this
        new_v = {:valueofPrompt => v}
      else 
        new_v = v
      end
      if new_v.class == String
          new_v = new_v.split(';') if new_v.match(/;/)  #If we have been handed multiple params (like "Mets;Yankees"), separate them out into an array so that Savon will pass them as two repeated elements ie <team>Mets</team> <team>Yankees</team>
      end

      clean_opts[k] = new_v
    end
    clean_opts
  end

end
