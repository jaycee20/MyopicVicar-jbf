module Freecen
  module Uninhabited
    UNOCCUPIED = 'u'
    BUILDING = 'b'
    MISSING_SCHEDULE = 'n'
    FAMILY_AWAY_VISITING = 'v'

    UNINHABITED_FLAGS = {
      UNOCCUPIED => 'Unoccupied',
      BUILDING => 'Building',
      MISSING_SCHEDULE => 'Missing Schedule',
      FAMILY_AWAY_VISITING => 'Family Away Visiting'
    }

    UNINHABITED_PATTERN = /[ubnv]/
  end

  module Languages
    WELSH = 'W'
    ENGLISH = 'E'
    BOTH = 'B'
    GAELIC = 'G'

    LANGUAGE_FLAGS = {
      WELSH => 'Welsh',
      ENGLISH => 'English',
      BOTH => 'Both',
      GAELIC => 'Gaelic'
    }
  end

  module Sexes
    MALE = 'M'
    FEMALE = 'F'

    SEX_FLAGS = {
      MALE => 'Male',
      FEMALE => 'Female'
    }
  end

  module MaritalStatus
    SINGLE = 'S'
    MARRIED = 'M'
    WIDOWED = 'W'

    MARITAL_STATUS_FLAGS = {
      SINGLE => 'Single',
      MARRIED => 'Married',
      WIDOWED => 'Widowed'
    }
  end

  module SpecialEnumerationDistricts
    CODES = ['None', 'Barracks & Military Quarters', 'HM Ships, at Home', 'Workhouses & Pauper Schools', 'Hospitals (Sick, Convalescent, Incurables)',
             'Lunatic Asylums', 'Prisons', 'Certified Reformatory & Industrial Schools', 'Merchant Vessels & Lighthouses', 'Schools']
  end

  FIELD_NAMES = { "0" => 'Civil Parish', "1" => 'Enumeration District', "2" => 'Folio', "3" => 'Page', "4" => 'Dwelling', "8" => 'Individual' }
  CENSUS_YEARS_ARRAY = ['1841', '1851', '1861', '1871', '1881', '1891', '1901', '1911'].freeze
  CHAPMAN_CODE_ELIMINATIONS = ['England', 'Scotland', 'Wales', 'Ireland', 'Unknown', 'Clwyd', 'Dyfed', 'Gwent', 'Gwynedd', 'Powys', 'Mid Glamorgan',
                               'South Glamorgan', 'West Glamorgan', 'Borders', 'Central', 'Dumfries and Galloway', 'Grampian', 'Highland', 'Lothian',
                               'Orkney Isles', 'Shetland Isles', 'Strathclyde', 'Tayside', 'Western Isles', 'Other Locations'].freeze

  STANDARD_FIELD_NAMES = ['civil_parish', 'enumeration_district', 'folio_number', 'page_number', 'schedule_number', 'house_number',
                          'house_or_street_name', 'uninhabited_flag', 'surname', 'forenames', 'name_flag', 'relationship', 'marital_status', 'sex', 'age',
                          'detail_flag', 'occupation', 'occupation_category', 'occupation_flag', 'verbatim_birth_county', 'verbatim_birth_place',
                          'birth_place_flag', 'disability', 'language', 'notes'].freeze
  ADDITIONAL_FIELD_NAMES = ['deleted_flag', 'ecclesiastical_parish'].freeze

  FIELD_NAMES_1901 = ['at_home', 'rooms'].freeze

  LINE1 = ['Civil Parish', 'ED', 'Folio', 'Page', 'Schd', 'House', 'Address', 'X', 'Surname', 'Forenames', 'X', 'Rel.', 'C', 'Sex', 'Age', 'X',
           'Occupation', 'E', 'X', 'CHP', 'Place of birth', 'X', 'Dis.', 'W', 'Notes', 'deleted', 'ecclesiastical'].freeze
  LINE2 = ['abcdefghijklmnopqrst', '###a', '####a', '####', '###a', '####a', 'abcdefghijklmnopqrstuvwxyzabcd', 'X', 'abcdefghijklmnopqrstuvwx',
           'abcdefghijklmnopqrstuvwx', 'X', 'abcdef', 'C', 'S', '###a', 'X', 'abcdefghijklmnopqrstuvwxyzabcd', 'E', 'X', 'abc',
           'abcdefghijklmnopqrst', 'X', 'abcdef,W,abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqr', 'd', 'abcdefgh'].freeze


end
