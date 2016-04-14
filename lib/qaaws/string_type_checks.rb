require 'active_support/core_ext'

class String
    def parses_numeric?
      true if Float(self) rescue false
    end

    def parses_date?
      true if Date.parse(self) rescue false
    end

    def parses_datetime?
      true if DateTime.parse(self) rescue false
    end 
end
