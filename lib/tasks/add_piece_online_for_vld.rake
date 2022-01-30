namespace :freecen do

  desc 'All pieces put to online'
  task :add_piece_online_for_vld, %i[lim fix] => :environment do |_t, args|
    # Print the time before start the process
    start_time = Time.now
    limit = args.lim.to_i

    fixit = args.fix.to_s == 'Y' ? true : false
    p "Starting vld checks at #{start_time} with limit #{limit} with fix  #{fixit}"

    # Call the RefreshUcfList library class file with passing the model name as parameter
    # FreecenPiece.no_timeout.each do |piece|
    #  piece.num_dwellings = piece.freecen_dwellings.count
    #  piece.save
    # end
    number = 0
    missing = 0
    processed = 0
    Freecen1VldFile.no_timeout.order_by(_id: -1).each do |file|
      number += 1
      break if number == limit + 1

      p number if (number / 100) * 100 == number
      freecen1_piece = FreecenPiece.find_by(_id: file.freecen_piece_id)
      p "#{file.file_name} has no freecen1 piece" if freecen1_piece.blank?
      p file if freecen1_piece.blank?
      missing += 1 if freecen1_piece.blank?
      next if freecen1_piece.blank?

      piece2_number = Freecen2Piece.calculate_freecen2_piece_number(freecen1_piece)
      freecen2_piece = Freecen2Piece.find_by(number: piece2_number)

      if freecen2_piece.blank?

        p "#{piece2_number} for #{file.file_name} is missing"
      elsif !freecen2_piece.status == 'Online'
        p "#{piece2_number} status for #{file.file_name} is missing and added"
        p freecen2_piece
        freecen2_piece.update_attributes(status: 'Online', status_date: file._id.generation_time.to_datetime.in_time_zone('London')) if fixit
      end

      regexp = BSON::Regexp::Raw.new('^' + piece2_number + '\D')
      parts = Freecen2Piece.where(number: regexp)
      unless parts.count.zero?
        parts.each do |part|
          processed += 1
          part.update_attributes(status: 'Online', status_date: file._id.generation_time.to_datetime.in_time_zone('London'), shared_vld_file: file.id) if fixit
          p "Setting #{part.number} to online"
          p part
          p file
        end
      end
    end
    number -= 1 if number == limit + 1
    running_time = Time.now - start_time
    p "Processed #{number} files #{processed} updates in time #{running_time} with #{missing} on-line files missing"
  end
end