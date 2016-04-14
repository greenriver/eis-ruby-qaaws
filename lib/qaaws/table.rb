class Qaaws
  class Table
    def initialize(tbl)
      #Convert numbers stored as strings to proper numbers.
      #@table = tbl.map {|row| Hash[ row.map {|k,v| [k, (numeric?(v) ? Float(v) : v.to_s)]} ]}
      # may want to use this somewhere later if val.respond_to?(:strftime) val.strftime("%s").to_i * 1000
      @table = tbl
    end

    def raw_table
      @table
    end

    def to_json
      @table.to_json
    end
  end
end
