class Freecen2Piece
  include Mongoid::Document
  include Mongoid::Timestamps::Short
  require 'freecen_constants'
  # 1841       HO107 plus 3 digits for the piece number
  #              HS4 plus 5 digits; 3 for the piece number and the 2 (most significant digits) for the Parish number

  # 1851       HO107 plus 4 digits for the piece number. So this year starts at 1000. It is uploaded to FreeCEN as HO51 to comply with the old 8 digit filename standard.
  #              HS5 plus 5 digits; 3 for the piece number and the 2 (most significant digits) for the Parish number

  # 1861       RG9 or RG09 plus 4 digits for the piece number
  #               RS6 plus 5 digits  3 for the piece number and the 2 (most significant digits) for the Parish number

  # 1871       RG10 plus 4 digits
  #                RS7 plus 5 digits  3 for the piece number and the 2 (most significant digits) for the Parish number

  # 1881       RG11 plus 4 digits
  #                RS8 plus 5 digits  3 for the piece number and the 2 (most significant digits) for the Parish number

  # 1891       RG12 plus 4 digits
  #              There are none for Scotland but I would anticipate RS9

  #1901       RG13 plus 4 digits

  #1911       RG14 plus 4 digits


  field :name, type: String
  validates :name, presence: true
  field :chapman_code, type: String
  validates_inclusion_of :chapman_code, in: ChapmanCode.values
  field :tnaid, type: String
  field :number, type: String
  validates :number, presence: true
  field :year, type: String
  validates_inclusion_of :year, in: Freecen::CENSUS_YEARS_ARRAY
  field :code, type: String
  field :notes, type: String
  field :prenote, type: String
  field :civil_parish_names, type: String
  field :reason_changed, type: String


  field :parish_number, type: String
  field :film_number, type: String

  field :status, type: String
  field :remarks, type: String
  field :remarks_coord, type: String # visible to coords, not public
  field :online_time, type: Integer
  field :num_individuals, type: Integer, default: 0

  belongs_to :freecen2_district, optional: true, index: true

  delegate :name, :tnaid, :code, :note, to: :freecen2_district, prefix: :district, allow_nil: true

  belongs_to :freecen2_place, optional: true, index: true
  has_many :freecen2_civil_parishes, dependent: :restrict_with_error
  has_many :freecen_dwellings, dependent: :restrict_with_error
  has_many :freecen_csv_files, dependent: :restrict_with_error
  has_many :freecen_individuals, dependent: :restrict_with_error

  index({ chapman_code: 1, year: 1, name: 1 }, name: 'chapman_code_year_name')
  index({ chapman_code: 1, name: 1 }, name: 'chapman_code_name')
  index({ name: 1 }, name: 'chapman_code_name')

  class << self
    def chapman_code(chapman)
      where(chapman_code: chapman)
    end

    def year(year)
      where(year: year)
    end

    def status(status)
      where(status: status)
    end

    def valid_series?(series)
      return true if %w[HO107 RG9 RG10 RG11 RG12 RG13 RG14].include?(series.upcase)

      # Need to add Scotland and Ireland
      false
    end

    def extract_year_and_piece(description, chapman_code)
      # Need to add Ireland
      remove_extension = description.split('.')
      parts = remove_extension[0].split('_')
      case parts[0].upcase
      when 'RG9'
        year = '1861'
        census_fields = Freecen::CEN2_1861
      when 'RG10'
        year = '1871'
        census_fields = Freecen::CEN2_1871
      when 'RG11'
        year = '1881'
        census_fields = Freecen::CEN2_1881
      when 'RG12'
        year = '1891'
        census_fields = Freecen::CEN2_1891
      when 'RG13'
        year = '1901'
        census_fields = Freecen::CEN2_1901
      when 'RG14'
        year = '1911'
        census_fields = Freecen::CEN2_1911
      when 'HO107'
        year = parts[1].delete('^0-9').to_i <= 1465 ? '1841' : '1851'
        census_fields = parts[1].delete('^0-9').to_i <= 1465 ? Freecen::CEN2_1841 : Freecen::CEN2_1851
      when 'HS51'
        year = parts[1].delete('^0-9')[2..3] == '51' ? '1851' : '1841'
        census_fields = parts[1].delete('^0-9')[2..3] == '51' ? Freecen::CEN2_SCT_1851 : Freecen::CEN2_SCT_1841
      when 'RS6'
        year = '1861'
        census_fields = Freecen::CEN2_SCT_1861
      when 'RS7'
        year = '1871'
        census_fields = Freecen::CEN2_SCT_1871
      when 'RS8'
        year = '1881'
        census_fields = Freecen::CEN2_SCT_1881
      when 'RS9'
        year = '1891'
        census_fields = Freecen::CEN2_SCT_1891
      when 'RS10'
        year = '1901'
        census_fields = Freecen::CEN2_SCT_1901
      when 'RS11'
        year = '1911'
        census_fields = Freecen::CEN2_SCT_1911
      end
      piece = parts[0] + '_' + parts[1]
      [year, piece, census_fields]
    end

    def county_year_totals(chapman_code)
      totals_pieces = {}
      Freecen::CENSUS_YEARS_ARRAY.each do |year|
        totals_pieces[year] = 0
        Freecen2District.chapman_code(chapman_code).year(year).each do |district|
          totals_pieces[year] = totals_pieces[year] + district.freecen2_pieces.count
        end
      end
      totals_pieces
    end

    def grand_totals(pieces)
      grand_pieces = pieces.values.sum
      grand_pieces
    end

    def county_district_year_totals(id)
      totals_district_pieces = {}
      Freecen::CENSUS_YEARS_ARRAY.each do |year|
        totals_district_pieces[year] = Freecen2Piece.where(freecen2_district_id: id, year: year).count
      end
      totals_district_pieces
    end

    def grand_year_totals
      totals_pieces = {}
      totals_pieces_online = {}
      totals_individuals = {}
      totals_dwellings = {}
      Freecen::CENSUS_YEARS_ARRAY.each do |year|
        totals_dwellings[year] = 0
        totals_individuals[year] = Freecen2Piece.status('Online').year(year).sum(:num_individuals)
        totals_pieces[year] = Freecen2iece2.year(year).count
        totals_pieces_online[year] = Freecen2Piece.status('Online').year(year).length
        Freecen2Piece.status('Online').year(year).each do |piece|
          totals_dwellings[year] = totals_dwellings[year] + piece.freecen_dwellings.count
        end
      end
      [totals_pieces, totals_pieces_online, totals_individuals, totals_dwellings]
    end

    def missing_places(chapman_code)
      Freecen2Piece.where(chapman_code: chapman_code, freecen2_place_id: nil).all.order_by(name: 1, year: 1)
    end
  end

  def add_update_civil_parish_list
    return nil if freecen2_civil_parishes.blank?

    @civil_parish_names = ''
    freecen2_civil_parishes.order_by(name: 1).each_with_index do |parish, entry|
      if entry.zero?
        @civil_parish_names = parish.add_hamlet_township_names.empty? ? parish.name : parish.name + ', ' + parish.add_hamlet_township_names
      else
        @civil_parish_names = parish.add_hamlet_township_names.empty? ? @civil_parish_names + ', ' + parish.name : @civil_parish_names + ', ' +
          parish.name + parish.add_hamlet_township_names
      end
    end
    @civil_parish_names
  end

  def piece_names
    pieces = Freecen2Piece.chapman_code(chapman_code).all.order_by(name: 1)
    @pieces = []
    pieces.each do |piece|
      @pieces << piece.name
    end
    @pieces = @pieces.uniq.sort
  end

  def piece_place_names
    places = Freecen2Place.chapman_code(chapman_code).all.order_by(place_name: 1)
    @places = []
    places.each do |place|
      @places << place.place_name
      place.alternate_freecen2_place_names.each do |alternate_name|
        @places << alternate_name.alternate_name
      end
    end
    @places = @places.uniq.sort
  end

  def piece_place_id(place_name)
    place = Freecen2Place.find_by(chapman_code: chapman_code, place_name: place_name) if chapman_code.present?
    place = place.present? ? place.id : ''
  end

  def propagate_freecen2_place(old_place, old_name)
    new_place = freecen2_place_id
    new_name = name
    return if (new_place.to_s == old_place.to_s) && (new_name == old_name)

    Freecen2Piece.where(chapman_code: chapman_code, name: old_name).each do |piece|
      if piece.id != _id
        piece.update_attributes(name: new_name)
      end
      old_piece_place = piece.freecen2_place_id
      piece.update_attributes(freecen2_place_id: new_place) if old_piece_place.blank? || old_piece_place.to_s == old_place.to_s
      piece.freecen2_civil_parishes.each do |civil_parish|
        old_civil_parish_place = civil_parish.freecen2_place_id
        civil_parish.update_attributes(freecen2_place_id: new_place) if old_civil_parish_place.blank? || old_civil_parish_place.to_s == old_place.to_s
      end
    end
    Freecen2Piece.where(chapman_code: chapman_code, name: name).each do |piece|
      old_place_name = piece.freecen2_place_id
      piece.update_attributes(freecen2_place_id: new_place) if old_place_name.blank? || old_place_name.to_s == old_place.to_s
      piece.freecen2_civil_parishes.each do |civil_parish|
        old_civil_parish_place = civil_parish.freecen2_place_id
        civil_parish.update_attributes(freecen2_place_id: new_place) if old_civil_parish_place.blank? || old_civil_parish_place.to_s == old_place.to_s
      end
    end
  end

  def update_freecen2_place
    result, place_id = Freecen2Place.valid_place(chapman_code, name)
    update_attributes(freecen2_place_id: place_id) if result
  end

  def update_tna_change_log(userid)
    tna = TnaChangeLog.create(userid: userid, year: year, chapman_code: chapman_code, parameters: previous_changes, tna_collection: "#{self.class}")
    tna.save
  end
end
