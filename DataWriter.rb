require 'json'
require 'csv'

module DataWriter
  # writes CSV from json document using titles
  def self.write_csv(type, final_arr)
    csv_data = CSV.generate do |csv|
      val = []
      final_arr[0][0].each do |title|
        val << title
      end
      csv << val
      final_arr[1].each do |elem|
        elem.each do |doc|
          data = []
          json_doc = JSON.generate(doc)
          json_doc = JSON.parse(json_doc)
          final_arr[0][0].each do |key|
            key_array = key.split('.')
            data << get_nested_val(key_array, json_doc)
          end
          csv << data
        end
      end
    end
    File.write("data_dump/#{type}_details.csv", csv_data)
  end

  # reads csv and generates a hash payload for API calls
  def self.build_payload_from_csv(csv, obj)
    payload = {}
    csv.each do |row|
      nested_val = DataWriter.get_nested_val(row.last.split('.'), obj)
      nested_val = nested_val.to_s unless nested_val.is_a? (String)
      nested_val = nested_val.strip unless nested_val.nil?
      payload.store(row.first, nested_val)
    end
    return payload
  end

  # parse the nested values within the JSON doc
  def self.get_nested_val(key_array, json_doc)
    current_doc = json_doc
    get_val = nil
    key_array.each do |key|
      if current_doc.nil?
        return nil
      else
        current_doc = current_doc[key]
        if current_doc.is_a? (String)
          current_doc = Formatter.remove_non_ascii(current_doc)
          current_doc = Formatter.remove_escape_sequence(current_doc)
        end
        get_val = current_doc
      end
    end
    return get_val
  end
end
