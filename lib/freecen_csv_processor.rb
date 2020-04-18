# -*- coding: utf-8 -*-
class FreecenCsvProcessor
  # This class processes a file or files of CSV records.
  #It converts them into entries and stores them in the freereg1_csv_entries     collection
  require 'csv'
  require 'email_veracity'
  require 'text'
  require 'unicode'
  require 'chapman_code'
  require "#{Rails.root}/app/models/freecen_csv_file"
  require "#{Rails.root}/app/models/freecen_csv_entry"
  require 'record_type'
  require 'register_type'
  require 'digest/md5'
  require 'get_files'
  require "#{Rails.root}/app/models/userid_detail"
  require 'freecen_validations'
  require 'freecen_constants'
  #:create_search_records has values create_search_records or no_search_records
  #:type_of_project has values waiting, range or individual
  #:force_rebuild causes all files to be processed
  #:file_range

  # normally run by the rake task build:freereg_new_update[create_search_records,individual,no,userid/filename] or
  # build:freereg_new_update[create_search_records,waiting,no,a-9] or
  # build:freereg_new_update[create_search_records,range,no,a]


  # It uses FreecenCsvProcessor as a class
  # The main entry point is activate_project to set up an instance of FreecenCsvProcessor to communication with the userid and the manager
  # and control the flow
  # CsvFiles gets the files to be processed
  # We then cycle through a single file in CsvFile
  # CsvFile has a_single_file_process method that controls the ingest and processing of the data from the file
  # through methods contained in CsvRecords and CsvRecord.
  # CsvRecords looks after the extraction of the header information including the new DEF header which is used
  # to permit different CsvFile field structures. It also extracts the data @data_lines.
  # CsvRecord is used to convert the csvrecord into a freereg1_csv_entry

  # note each class inherits from its superior

  #:message_file is the log file where system and processing messages are written
  attr_accessor :freecen_files_directory, :create_search_records, :type_of_project, :force_rebuild, :info_messages,
    :file_range, :message_file, :member_message_file, :project_start_time, :total_records, :total_files, :total_data_errors, :flexible

  def initialize(arg1, arg2, arg3, arg4, arg5, arg6)
    @create_search_records = arg1
    @file_range = arg4
    @force_rebuild = arg3
    @freecen_files_directory = Rails.application.config.datafiles
    @message_file = define_message_file
    @project_start_time = Time.now
    @total_data_errors = 0
    @total_files = 0
    @total_records = 0
    @type_of_project = arg2
    @flexible = arg5 == 'Traditional' ? false : true
    @type_of_processing = arg6
    @info_messages = @type_of_processing == 'Check(Info)' ? true : false
    EmailVeracity::Config[:skip_lookup] = true
  end

  def self.activate_project(create_search_records, type, force, range, type_of_field, type_of_processing)
    force, create_search_records = FreecenCsvProcessor.convert_to_bolean(create_search_records, force)
    @project = FreecenCsvProcessor.new(create_search_records, type, force, range, type_of_field, type_of_processing)
    @project.write_log_file("Started freecen csv file processor project. #{@project.inspect} using website #{Rails.application.config.website}. <br>")

    @csvfiles = CsvFiles.new(@project)
    success, files_to_be_processed = @csvfiles.get_the_files_to_be_processed
    if !success || (files_to_be_processed.present? && files_to_be_processed.length.zero?)
      @project.write_log_file('processing terminated as we have no records to process. <br>')
      return
    end
    @project.write_log_file("#{files_to_be_processed.length}\t files selected for processing. <br>")
    files_to_be_processed.each do |file_name|
      @hold_name = file_name
      @csvfile = CsvFile.new(@hold_name, @project)
      success, @records_processed, @data_errors = @csvfile.a_single_csv_file_process
      if success
        #p "processed file"
        @project.total_records = @project.total_records + @records_processed unless @records_processed.nil?
        @project.total_data_errors = @project.total_data_errors + data_errors unless @data_errors
        @project.total_files = @project.total_files + 1
      else
        #p "failed to process file"
        @csvfile.communicate_failure_to_member(@records_processed)
        @csvfile.clean_up_physical_files_after_failure(@records_processed)
        # @project.communicate_to_managers(@csvfile) if @project.type_of_project == "individual"
      end
      sleep(300) if Rails.env.production?
    end
    # p "manager communication"
    #@project.communicate_to_managers(@csvfile) if files_to_be_processed.length >= 2
    at_exit do
      # p "goodbye"
    end
  end

  def self.delete_all
    FreecenCsvEntry.delete_all
    FreecenCsvFile.delete_all
    SearchRecord.delete_freecen_individual_entries
  end

  def self.qualify_path(path)
    unless path.match(/^\//) || path.match(/:/) # unix root or windows
      path = File.join(Rails.root, path)
    end
    path
  end

  def communicate_to_managers
    records = @total_records
    average_time = records == 0 ? 0 : average_time = (Time.new.to_i - @project_start_time.to_i) * 1000 / records
    write_messages_to_all("Created  #{records} entries at an average time of #{average_time}ms per record at #{Time.new}. <br>", false)
    file = @message_file
    #@message_file.close if @project.type_of_project == "individual"
    user = UseridDetail.where(userid: "Captkirk").first
    UserMailer.update_report_to_freereg_manager(file, user).deliver_now
  end

  def self.convert_to_bolean(create_search_records, force)
    create_search_records = create_search_records == 'create_search_records' ? true : false
    force = force == 'force_rebuild' ? true : false

    [force, create_search_records]
  end

  def define_message_file
    time = Time.new
    tnsec = time.nsec / 1000
    time = time.to_i.to_s + tnsec.to_s
    file_for_warning_messages = Rails.root.join('log', "freecen_csv_processing_messages_#{time}.log")
    message_file = File.new(file_for_warning_messages, 'w')
    message_file.chmod(0664)
    message_file
  end

  def write_member_message_file(message)
    member_message_file.puts message
  end

  def write_messages_to_all(message, no_member_message)
    # avoids sending the message to the member if no_member_message is false
    message = message.encode(message.encoding, universal_newline: true) if message.present?
    write_log_file(message) if message.present?
    write_member_message_file(message) if no_member_message && message.present?
  end

  def write_log_file(message)
    message_file.puts message
  end
end

class CsvFiles < FreecenCsvProcessor
  def initialize(project)
    @project = project
  end

  def get_the_files_to_be_processed
    #  p "Getting files"
    case @project.type_of_project
    when 'waiting'
      files = get_the_waiting_files_to_be_processed
    when 'range'
      files = get_the_range_files_to_be_processed
    when 'individual'
      files = get_the_individual_file_to_be_processed
    end
    [true, files]
  end

  # GetFile is a lib task
  def get_the_individual_file_to_be_processed
    # p "individual file selection"
    files = GetFiles.get_all_of_the_filenames(@project.freecen_files_directory, @project.file_range)
    files
  end

  def get_the_range_files_to_be_processed
    # p "range file selection"
    files = GetFiles.get_all_of_the_filenames(@project.freecen_files_directory, @project.file_range)
    files
  end

  def get_the_waiting_files_to_be_processed
    # p "waiting file selection"
    physical_waiting_files = PhysicalFile.waiting.all.order_by(waiting_date: 1)
    files = []
    physical_waiting_files.each do |file|
      files << File.join(@project.freecen_files_directory, file.userid, file.file_name)
    end
    files
  end
end

class CsvFile < CsvFiles

  # initializes variables
  # gets information on the file to be processed

  attr_accessor :header, :list_of_registers, :header_error, :system_error, :data_hold,:dwelling_number, :sequence_in_household,
    :array_of_data_lines, :default_charset, :file, :file_name, :userid, :uploaded_date, :slurp_fail_message, :field_specification,
    :file_start, :file_locations, :data, :unique_locations, :unique_existing_locations, :full_dirname, :chapman_code, :traditional,
    :all_existing_records, :total_files, :total_records, :total_data_errors, :total_header_errors, :place_id, :civil_parish,
    :enumeration_district, :folio, :page, :year, :piece, :schedule, :folio_suffix, :schedule_suffix, :total_errors, :total_warnings, :total_info

  def initialize(file_location, project)
    @project = project
    @file_location = file_location
    standalone_filename = File.basename(@file_location)
    @full_dirname = File.dirname(@file_location)
    parent_dirname = File.dirname(@full_dirname)
    user_dirname = @full_dirname.sub(parent_dirname, '').gsub(File::SEPARATOR, '')
    @all_existing_records = {}
    @array_of_data_lines = Array.new {Array.new}
    @data = {}
    @default_charset = "UTF-8"
    @file_locations = {}
    @file_name = standalone_filename
    @file_start =  nil
    @uploaded_date = Time.new
    @uploaded_date = File.mtime(@file_location) if File.exists?(@file_location)
    @header_error = []
    @header = {}
    @header[:digest] = Digest::MD5.file(@file_location).hexdigest if File.exists?(@file_location)
    @header[:file_name] = standalone_filename #do not capitalize filenames
    @header[:userid] = user_dirname
    @header[:uploaded_date] = @uploaded_date
    server = SoftwareVersion.extract_server(Socket.gethostname)
    @software_version = SoftwareVersion.server(server).app('freecen').control.first
    @header[:software_version] = ''
    @header[:search_record_version] = ''
    @header[:software_version] = @software_version.version if @software_version.present?
    @header[:search_record_version] = @software_version.last_search_record_version if @software_version.present?
    @place_id = nil
    @slurp_fail_message = nil
    @userid = user_dirname
    @total_data_errors = 0
    @total_files = 0
    @total_header_errors = 0
    @total_records = 0
    @year = ''
    @piece = nil
    @chapman_code
    @civil_parish = ''
    @enumeration_district = ''
    @folio = 0
    @folio_suffix = nil
    @page = 0
    @schedule = 0
    @schedule_suffix = nil
    @total_errors = 0
    @total_warnings = 0
    @total_info = 0
    @dwelling_number = 0
    @sequence_in_household = 0
    @field_specication = {}
    @traditional = 2

  end

  def a_single_csv_file_process
    # p "single csv file"
    success = true
    @project.member_message_file = define_member_message_file
    @file_start = Time.new
    p "FREECEN:CSV_PROCESSING: Started on the file #{@header[:file_name]} for #{@header[:userid]} at #{@file_start}"
    @project.write_log_file("******************************************************************* <br>")
    @project.write_messages_to_all("Started on the file #{@header[:file_name]} for #{@header[:userid]} at #{@file_start}. <p>", true)
    success, message = ensure_processable? unless @project.force_rebuild
    # p "finished file checking #{message}. <br>"
    return [false, message] unless success

    success, message, @year, @piece = extract_piece_year_from_file_name(@file_name)
    @chapman_code = @piece.chapman_code if @piece.present?
    @project.write_messages_to_all(message, true) unless success
    @project.write_messages_to_all("Working on #{@piece.district_name} for #{@year}, in #{@piece.chapman_code}", true) if success
    return [false, message] unless success

    success, message = slurp_the_csv_file
    # p "finished slurp #{success} #{message}"
    return [false, message] unless success

    @csv_records = CsvRecords.new(@array_of_data_lines, self, @project)
    success, reduction = @csv_records.process_header_fields

    return [false, "initial @data_lines made no sense extracted #{message}. <br>"] unless success || [1, 2].include?(reduction)

    success, records_processed, data_records = @csv_records.extract_the_data(reduction)

    return [success, "Data not extracted #{records_processed}. <br>"] unless success

    success, freecen_csv_file = write_freecen_csv_file if success

    return [success, "File not saved. <br>"] unless success

    success = write_freecen_csv_entries(data_records, freecen_csv_file) if success

    success, message = clean_up_supporting_information(records_processed) if success

    return [success, "clean up failed #{message}. <br>"] unless success
    # p "finished clean up
    time = ((Time.new.to_i - @file_start.to_i) * 1000) / records_processed unless records_processed.zero?
    @project.write_messages_to_all("Created  #{records_processed} entries at an average time of #{time}ms per record at #{Time.new}. <br>",true)

    success, message = communicate_file_processing_results
    # p "finished com"
    return [success, "communication failed #{message}. <br>"] unless success

    [true, records_processed, @total_data_errors]
  end

  def extract_piece_year_from_file_name(file_name)
    if FreecenValidations.fixed_valid_piece?(file_name)
      success = true
      year, piece = FreecenPiece.extract_year_and_piece(file_name)
      actual_piece = FreecenPiece.where(year: year, piece_number: piece).first
      if actual_piece.blank?
        message = "Error: there is no piece for #{file_name} in the database}. <br>"
        success = false
      end
    else
      message = "Error: File name does not have a valid piece number. It is #{file_name}. <br>"
      success = false
    end

    [success, message, year, actual_piece]
  end

  def check_and_set_characterset(code_set, csvtxt)
    # if it looks like valid UTF-8 and we know it isn't
    # Windows-1252 because of undefined characters, then
    # default to UTF-8 instead of Windows-1252
    if code_set.nil? || code_set.empty? || code_set == 'chset'
      # @project.write_messages_to_all("Checking for undefined with #{code_set}",false)
      if csvtxt.index(0x81.chr) || csvtxt.index(0x8D.chr) ||
          csvtxt.index(0x8F.chr) || csvtxt.index(0x90.chr) ||
          csvtxt.index(0x9D.chr)
        # p 'undefined Windows-1252 chars, try UTF-8 default'
        # @project.write_messages_to_all("Found undefined}",false)
        csvtxt.force_encoding('UTF-8')
        code_set = 'UTF-8' if csvtxt.valid_encoding?
        csvtxt.force_encoding('ASCII-8BIT') # convert later with replace
      end
    end
    code_set = self.default_charset if (code_set.blank? || code_set == 'chset')
    code_set = "UTF-8" if (code_set.upcase == "UTF8")
    #Deal with the cp437 code which is IBM437 in ruby
    code_set = "IBM437" if (code_set.upcase == "CP437")
    #Deal with the macintosh instruction in freereg1
    code_set = "macRoman" if (code_set.downcase == "macintosh")
    code_set = code_set.upcase if code_set.length == 5 || code_set.length == 6
    message = "Invalid Character Set detected #{code_set} have assumed Windows-1252. <br>" unless Encoding.name_list.include?(code_set)
    code_set = self.default_charset unless Encoding.name_list.include?(code_set)
    self.header[:characterset] = code_set
    # convert to UTF-8 if we didn't already. If our
    # preference is to fail when invalid characters or
    # undefined characters are found (so we can fix the
    # file or specified encoding) instead of silently
    # replacing bad characters with the undefined character
    # symbol, the two replacement options can be removed
    unless csvtxt.encoding == 'UTF-8'
      csvtxt.force_encoding(code_set)
      self.slurp_fail_message = "the processor failed to convert to UTF-8 from character set #{code_set}. <br>"
      csvtxt = csvtxt.encode('UTF-8', invalid: :replace, undef: :replace)
      self.slurp_fail_message = nil # no exception thrown
    end
    [code_set, message, csvtxt]
  end

  def check_file_exists?
    # make sure file actually exists
    message = "The file #{@file_name} for #{@userid} does not exist. <br>"
    return [true, 'OK'] if File.exist?(@file_location)

    @project.write_messages_to_all(message, true)
    [false, message]
  end

  def check_file_is_not_locked?(batch)
    return [true, 'OK'] if batch.blank?

    message = "The file #{batch.file_name} for #{batch.userid} is already on system and is locked against replacement. <br>"
    return [true, 'OK'] unless batch.locked_by_transcriber || batch.locked_by_coordinator

    @project.write_messages_to_all(message, true)
    [false, message]
  end

  def check_userid_exists?
    message = "The #{@userid} userid does not exist. <br>"
    return [true, 'OK'] if UseridDetail.userid(@userid).first.present?

    @project.write_messages_to_all(message, true)
    [false, message]
  end

  def clean_up_message

    #File.delete(@project.message_file) if @project.type_of_project == 'individual' && File.exists?(@project.message_file) && !Rails.env.test?

  end

  def clean_up_physical_files_after_failure(message)
    batch = PhysicalFile.userid(@userid).file_name(@file_name).first
    return true if batch.blank? || message.blank?

    PhysicalFile.remove_waiting_flag(@userid,@file_name)
    batch.delete if message.include?("header errors") || message.include?("does not exist. ") || message.include?("userid does not exist. ")
  end

  def clean_up_supporting_information(records_processed)
    if records_processed.blank? || records_processed.zero?
      batch = PhysicalFile.userid(@userid).file_name(@file_name).first
      return true if batch.blank?

      batch.delete
    else
      physical_file_clean_up_on_success
    end
    true
  end

  def communicate_failure_to_member(message)
    file = @project.member_message_file
    file.close
    copy_file_name = "#{@header[:file_name]}.txt"
    to = File.join(@full_dirname, copy_file_name)
    FileUtils.cp_r(file, to, remove_destination: true)
    UserMailer.batch_processing_failure(file, @userid, @file_name).deliver_now unless @project.type_of_project == "special_selection_1" ||  @project.type_of_project == "special_selection_2"
    clean_up_message
    true
  end

  def communicate_file_processing_results
    #p "communicating success"
    file = @project.member_message_file
    file.close
    copy_file_name = "#{@header[:file_name]}.txt"
    to = File.join(@full_dirname, copy_file_name)
    FileUtils.cp_r(file, to, remove_destination: true)
    UserMailer.batch_processing_success(file, @header[:userid],@header[:file_name]).deliver_now unless @project.type_of_project == "special_selection_1" ||  @project.type_of_project == "special_selection_2"
    clean_up_message
    true
  end

  def define_member_message_file
    time = Time.new
    tnsec = time.nsec / 1000
    time = time.to_i.to_s + tnsec.to_s
    file_for_member_messages = Rails.root.join('log', "#{userid}_member_update_messages_#{time}.log").to_s
    member_message_file = File.new(file_for_member_messages, 'w')
    member_message_file
  end


  def determine_if_utf8(csvtxt)
    # check for BOM and if found, assume corresponding
    # unicode encoding (unless invalid sequences found),
    # regardless of what user specified in column 5 since it
    # may have been edited and saved as unicode by coord
    # without updating col 5 to reflect the new encoding.
    # p "testing for BOM"
    if !csvtxt.nil? && csvtxt.length > 2
      if csvtxt[0].ord == 0xEF && csvtxt[1].ord == 0xBB && csvtxt[2].ord == 0xBF
        # p "UTF-8 BOM found"
        # @project.write_messages_to_all("BOM found",false)
        csvtxt = csvtxt[3..-1] # remove BOM
        code_set = 'UTF-8'
        self.slurp_fail_message = 'BOM detected so using UTF8. <br>'
        csvtxt.force_encoding(code_set)
        if !csvtxt.valid_encoding?
          # @project.write_messages_to_all("Not really a UTF8",false)
          # not really a UTF-8 file. probably was edited in
          # software that added BOM to beginning without
          # properly transcoding existing characters to UTF-8
          code_set = 'ASCII-8BIT'
          csvtxt.encode('ASCII-8BIT')
          csvtxt.force_encoding('ASCII-8BIT')
          # @project.write_messages_to_all("Not really ASCII-8BIT",false) unless csvtxt.valid_encoding?
        else
          self.slurp_fail_message = 'Using UTF8. <br>'
          csvtxt = csvtxt.encode('utf-8', undef: :replace)
        end
      else
        code_set = nil
        # No BOM
        self.slurp_fail_message = nil
      end
    else
      # No BOM
      self.slurp_fail_message = nil
      code_set = nil
    end
    # @project.write_messages_to_all("Code set #{code_set}", false)

    [code_set, csvtxt]
  end

  def ensure_processable?
    success, message = check_file_exists?
    success, message = check_userid_exists? if success
    batch = FreecenCsvFile.userid(@userid).file_name(@file_name).first if success
    success, message = check_file_is_not_locked?(batch) if success
    return [true, 'OK'] if success

    return [false, message] unless success
  end

  def extract_the_array_of_lines(csvtxt)
    #now get all the data
    self.slurp_fail_message = "the CSV parser failed. The CSV file might not be formatted correctly. <br>"
    @array_of_data_lines = CSV.parse(csvtxt, { row_sep: "\r\n", skip_blanks: true })
    #remove zzz fields and white space
    @array_of_data_lines.each do |line|
      line.each_index    {|x| line[x] = line[x].gsub(/zzz/, ' ').gsub(/\s+/, ' ').strip unless line[x].nil? }
    end
    @slurp_fail_message = nil # no exception thrown
    true
  end

  def get_codeset_from_header(code_set, csvtxt)
    @slurp_fail_message = "CSV parse failure on first line. <br>"
    first_data_line = CSV.parse_line(csvtxt)
    @slurp_fail_message = nil # no exception thrown
    if !first_data_line.nil? && first_data_line[0] == "+INFO" && !first_data_line[5].nil?
      code_set_specified_in_csv = first_data_line[5].strip
      # @project.write_messages_to_all("Detecting character set found #{code_set_specified_in_csv}",false)
      if !code_set.nil? && code_set != code_set_specified_in_csv
        message = "ignoring #{code_set_specified_in_csv} specified in col 5 of .csv header because #{code_set} Byte Order Mark (BOM) was found in the file"
        # @project.write_messages_to_all(message,false)
      else
        # @project.write_messages_to_all("using #{code_set_specified_in_csv}",false)
        code_set = code_set_specified_in_csv
      end
    end
    return code_set
  end

  def physical_file_clean_up_on_success
    #p "physical file clean up on success"
    batch = PhysicalFile.userid(@userid).file_name(@file_name).first
    if batch.blank?
      batch = PhysicalFile.new(userid: @userid, file_name: @file_name, base: true, base_uploaded_date: Time.new)
      batch.save
    end
    if @project.create_search_records
      # we created search records so its in the search database database
      batch.update(file_processed: true, file_processed_date: Time.new, waiting_to_be_processed: false, waiting_date: nil)
    else
      #only checked for errors so file is not processed into search database
      batch.update(file_processed: false, file_processed_date: nil, waiting_to_be_processed: false, waiting_date: nil)
    end
  end

  def slurp_the_csv_file
    # p "starting the slurp"
    # read entire .csv as binary text (no encoding/conversion)
    success = true
    csvtxt = File.open(@file_location, 'rb', encoding: 'ASCII-8BIT:ASCII-8BIT') { |f| f.read }
    @project.write_messages_to_all('Empty file', true) if csvtxt.blank?
    return false if csvtxt.blank?

    code, csvtxt = determine_if_utf8(csvtxt)
    # code = get_codeset_from_header(code, csvtxt)
    code, message, csvtxt = self.check_and_set_characterset(code, csvtxt)
    csvtxt = self.standardize_line_endings(csvtxt)
    success = self.extract_the_array_of_lines(csvtxt)

    [success, message]
    #we ensure that processing keeps going by dropping out through the bottom
  end

  def standardize_line_endings(csvtxt)
    xxx = csvtxt.gsub(/\r?\n/, "\r\n").gsub(/\r\n?/, "\r\n")
    return xxx
  end

  def write_freecen_csv_file
    old_file = FreecenCsvFile.find_by(file_name: @file_name, chapman_code: @chapman_code)
    if old_file.present?
      FreecenCsvEntry.where(freecen_csv_file_id: old_file.id).destroy_all
      old_file.delete
    end
    new_file = FreecenCsvFile.new
    new_file.file_name = @file_name
    new_file.uploaded_date = @uploaded_date
    new_file.software_version = @software_version
    new_file.userid = @userid
    new_file.chapman_code = @chapman_code
    new_file.total_records = @total_records.to_i
    new_file.total_errors = @total_errors
    new_file.total_warnings = @total_warnings
    new_file.flexible = @project.flexible
    new_file.total_info = @total_info
    new_file.traditional = @traditional
    new_file.processed = @project.create_search_records
    new_file.year = @year
    new_file.field_specification = @field_specification
    piece.freecen_csv_files << new_file
    success = piece.save
    p new_file
    [success, new_file]
  end

  def write_freecen_csv_entries(records, file)
    records.each do |record|
      record[:piece_numer] = record[:piece].piece_number.to_i
      record[:piece] = nil
      record = record.delete_if {|key, value| key == :piece }
      freecen_csv_entry = FreecenCsvEntry.new(record)
      freecen_csv_entry.freecen_csv_file_id = file.id
      freecen_csv_entry.save
    end
    file.update(total_records: records.length) if records.present?
    true
  end
end

class CsvRecords < CsvFile
  require 'freecen_constants'

  attr_accessor :array_of_lines, :data_lines

  def initialize(data_array, csvfile, project)
    @project = project
    @csvfile = csvfile
    @array_of_lines = data_array
    @data_lines = Array.new { Array.new }
  end

  def process_header_fields
    # p "Getting header
    reduction = 0
    n = 0
    @project.write_messages_to_all("Error: line #{n} is empty", true) if @array_of_lines[n][0..24].all?(&:blank?)
    return [false, n] if @array_of_lines[n][0..24].all?(&:blank?)

    success, message, @csvfile.field_specification, @csvfile.traditional = line_one(@array_of_lines[n])
    if success
      reduction = reduction + 1
    else
      @project.write_messages_to_all(message, true)
      return [success, reduction]
    end
    success, message = line_two(@array_of_lines[n])
    if success
      reduction = reduction + 1
      @project.write_messages_to_all(message, true)
    end
    [success, reduction]
  end

  def line_one(line)
    if line[0..24].all?(&:present?)
      traditional = extract_traditonal_headers(line)
      success, message, field_specification = extract_field_headers(line)
    else
      message = 'INFO: line 1 Column field specification is missing.<br>'
      success = false
    end
    [success, message, field_specification, traditional]
  end

  def line_two(line)
    success = false
    if line[0].casecmp?('abcdefghijklmnopqrst')
      message = 'Info: line 2 field width specification detected and ignored'
      success = true
    end
    [success, message]
  end

  def extract_traditonal_headers(line)
    if line.length == 25
      traditional = 0
    elsif line.length > 25 && line[1] == 'ED'
      traditional = 1
    else
      traditional = 2
    end
    traditional
  end

  def extract_field_headers(line)
    line = line
    n = 0
    field_specification = {}
    success = true
    message = ''
    if these_are_these_old_headers?(line)
      line = convert_old_to_modern(line)
    end

    while line[n].present?
      Freecen::FIELD_NAMES_CONVERSION.key(line[n].downcase)
      if Freecen::FIELD_NAMES_CONVERSION.key?(line[n].downcase)
        field_specification[n] = Freecen::FIELD_NAMES_CONVERSION[line[n].downcase]
      else
        success = false
        message = message + "ERROR: column header at position #{n} is invalid  #{line[n]} "
      end
      n = n + 1
    end
    p field_specification
    [success, message, field_specification]
  end

  def these_are_these_old_headers?(line)
    result = false
    result = true if line[0].casecmp?('civil parish') && line[1].casecmp?('ed') && line[4].casecmp?('Schd')
    result
  end

  def convert_old_to_modern(line)
    line[7] = 'xu'
    line[10] = 'xn'
    line[15] = 'xd'
    line[18] = 'xo'
    line[21] = 'xb'
    line
  end

  # This extracts the header and entry information from the file and adds it to the database

  def extract_the_data(skip)
    p 'data'
    p skip
    skip = skip
    success = true
    data_lines = 0
    data_records = []
    @array_of_lines.each_with_index do |line, n|
      next if n < skip

      @project.write_messages_to_all("Error: line #{n} is empty.<br>", true) if line[0..24].all?(&:blank?)
      next if line[0..24].all?(&:blank?)

      @record = CsvRecord.new(line, @csvfile, @project)
      success, message, result = @record.extract_data_line(n)
      result[:flag] = true if result[:birth_place_flag].present? || result[:deleted_flag].present? || result[:individual_flag].present? ||
        result[:name_flag].present? || result[:occupation_flag].present? || (result[:uninhabited_flag].present? && result[:uninhabited_flag].downcase == 'x')
      data_records << result
      @csvfile.total_errors = @csvfile.total_errors + 1 if result[:error_messages].present?
      @csvfile.total_warnings = @csvfile.total_warnings + 1 if result[:warning_messages].present?
      @csvfile.total_info = @csvfile.total_info + 1 if result[:info_messages].present?
      @project.write_messages_to_all(message, true) unless success
      success = true
      data_lines = data_lines + 1
    end
    [success, data_lines, data_records]
  end

  def inform_the_user
    @csvfile.header_error.each do |error|
      @project.write_messages_to_all(error, true)
    end
  end
end

class CsvRecord < CsvRecords

  attr_accessor :data_line, :data_record, :civil_parish, :folio, :page, :dwelling, :individual

  def initialize(data_line, csvfile, project)
    @project = project
    @csvfile = csvfile
    @data_line = data_line
    @data_record = {}
    @data_record[:year] = @csvfile.year
    @data_record[:piece] = @csvfile.piece
    @data_record[:flexible] = @project.flexible
    @data_record[:error_messages] = ''
    @data_record[:warning_messages] = ''
    @data_record[:info_messages] = ''
    @data_record[:field_specification] = @csvfile.field_specification
  end

  def extract_data_line(num)
    @data_record[:record_number] = num
    @data_record[:messages] = @project.info_messages
    @data_record[:data_transition] = @csvfile.field_specification[first_field_present]
    convert_transition
    @data_record = load_data_record
    process_data_record(@data_record[:data_transition])
    # p @data_record
    # crash if num == 10
    [true, ' ', @data_record]
  end

  def convert_transition
    if @data_record[:data_transition] == 'civil_parish'
      @data_record[:data_transition] = 'Civil Parish'
    elsif %w[enumeration_district ecclesiastical_parish municipal_borough ward parliamentary_constituency
             school_board location_flag].include?(@data_record[:data_transition])
      @data_record[:data_transition] = 'Enumeration District'
    elsif @data_record[:data_transition] == 'folio_number'
      @data_record[:data_transition] = 'Folio'
    elsif @data_record[:data_transition] == 'page_number'
      @data_record[:data_transition] = 'Page'
    elsif %w[schedule_number house_number house_or_street_name uninhabited_flag address_flag].include?(@data_record[:data_transition])
      @data_record[:data_transition] = 'Dwelling'
    else
      @data_record[:data_transition] = 'Individual'
    end
  end

  def first_field_present
    @data_line.each_with_index do |field, n|
      @x = n
      break if field.present?
    end
    @x
  end

  def load_data_record
    @data_record[:field_specification].each_with_index do |(_key, field), n|
      break if field.blank?
      @data_record[field.to_sym] = @data_line[n]
    end
    @data_record
  end

  def process_data_record(record_type)
    case record_type
    when 'Civil Parish'
      extract_civil_parish_fields
    when 'Enumeration District'
      extract_enumeration_district_fields
    when 'Folio'
      extract_folio_fields
    when 'Page'
      extract_page_fields
    when 'Dwelling'
      extract_dwelling_fields
    when 'Individual'
      extract_individual_fields
    when 'Error'
      error_in_fields
    end
  end

  def extract_civil_parish_fields
    success, message, @csvfile.civil_parish = FreecenCsvEntry.validate_civil_parish(@data_record, @csvfile.civil_parish)
    @project.write_messages_to_all(message, true) unless message == ''
    extract_enumeration_district_fields
  end

  def extract_enumeration_district_fields
    success, message, @csvfile.enumeration_district = FreecenCsvEntry.validate_enumeration_district(@data_record, @csvfile.enumeration_district)
    @project.write_messages_to_all(message, true) unless message == ''
    extract_folio_fields
  end

  def extract_folio_fields
    success, message, @csvfile.folio, @csvfile.folio_suffix = FreecenCsvEntry.validate_folio(@data_record, @csvfile.folio, @csvfile.folio_suffix)
    @project.write_messages_to_all(message, true) unless message == ''
    extract_page_fields
  end

  def extract_page_fields
    success, message, @csvfile.page = FreecenCsvEntry.validate_page(@data_record, @csvfile.page)
    @project.write_messages_to_all(message, true) unless message == ''
    extract_dwelling_fields
  end

  def extract_dwelling_fields
    if @data_record[:house_number].blank? && @data_record[:house_or_street_name].blank? && @data_record[:schedule_number].blank?
      @data_record[:dwelling_number] = @csvfile.dwelling_number

    elsif['b', 'n', 'u', 'v'].include?(@data_record[:uninhabited_flag])
      @data_record[:dwelling_number] = @csvfile.dwelling_number + 1
      @csvfile.dwelling_number = @data_record[:dwelling_number]
    elsif @data_record[:house_number].blank? && @data_record[:house_or_street_name] == '-' && @data_record[:schedule_number] == '0'
      @data_record[:dwelling_number] = @csvfile.dwelling_number + 1
      @csvfile.dwelling_number = @data_record[:dwelling_number]
    else
      @data_record[:dwelling_number] = @csvfile.dwelling_number + 1
      @csvfile.dwelling_number = @data_record[:dwelling_number]
      @csvfile.sequence_in_household = 0
    end
    success, message, @csvfile.schedule, @csvfile.schedule_suffix = FreecenCsvEntry.validate_dwelling(@data_record, @csvfile.schedule, @csvfile.schedule_suffix)
    @project.write_messages_to_all(message, true) unless message == ''
    extract_individual_fields
  end

  def extract_individual_fields
    @data_record[:notes] = '' if @data_record[:notes] =~ /\[see mynotes.txt\]/
    return if ['b', 'n', 'u', 'v'].include?(@data_record[:uninhabited_flag])

    @data_record[:address_flag] = 'x' if @data_record[:uninhabited_flag] == 'x'
    @data_record[:dwelling_number] = @csvfile.dwelling_number
    @csvfile.sequence_in_household = @csvfile.sequence_in_household + 1
    @data_record[:sequence_in_household] = @csvfile.sequence_in_household
    success, message = FreecenCsvEntry.validate_individual(@data_record)
    @project.write_messages_to_all(message, true) unless message == ''
  end
end
