class CheckSearchRecordsForCorrectCounty

  require 'chapman_code'
  require "freereg1_csv_file"
  require "freereg1_csv_entry"
  require "search_record"
  include Mongoid::Document

  def self.process(limit,fix)
    file_for_warning_messages = "log/check_search_records_messages.log"
    FileUtils.mkdir_p(File.dirname(file_for_warning_messages) )
    message_file = File.new(file_for_warning_messages, "w")
    limit = limit.to_i
    puts "checking #{limit} documents for incorrect county in the search records collection with #{fix}"
    file_number = 0
    incorrect_files = 0
    incorrect_records = 0
    processing = 0
    number_processed = 0 
    files = Freereg1CsvFile.count
    p files
    Freereg1CsvFile.no_timeout.each do |my_file|
      processing = processing + 1
      number_processed = number_processed + 1
      file_number = file_number + 1
      break if file_number == limit
      break if file_number == files
      file_ok = my_file.check_county
      if !file_ok[0]
        incorrect_files = incorrect_files + 1
        message_file.puts "File,#{my_file.userid}, #{my_file.file_name},#{my_file.county},#{my_file.place},#{my_file.church_name},#{my_file.register_type}, #{file_ok[1]}"
        #message_file.puts my_entry
      end
      record_ok = true
      record_ok = my_file.check_search_record_location_and_county 
      if !record_ok[0]
        incorrect_records = incorrect_records + my_file.freereg1_csv_entries.count
        message_file.puts "Record,#{my_file.userid},#{my_file.file_name},has ,#{my_file.freereg1_csv_entries.count}, #{record_ok[1]}"
      end
      p number_processsed  if processing == 1000
      processing = 0 if processing == 1000
      if fix = "fix" && ( !file_ok[0] || !record_ok[0])
        my_file.correct_location
      end

    end
    puts "checked #{file_number} files there were #{incorrect_files} incorrect files and #{incorrect_records} incorrect search records"
    message_file.close 
    return
  end

end
