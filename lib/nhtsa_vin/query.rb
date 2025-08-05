require 'net/http'
require 'json'

module NhtsaVin
  class Query

    NHTSA_URL = 'https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/'.freeze

    attr_reader :vin, :url, :response, :data, :error, :error_code, :raw_response

    def initialize(vin, options = {})
      @vin = vin.strip.upcase
      @http_options = options[:http] || {}
      build_url
    end

    def get
      @raw_response = fetch
      begin
        return if @raw_response.nil? || (json_response = JSON.parse(@raw_response)).nil?
        parse(json_response)
      rescue JSON::ParserError
        @valid = false
        @error = 'Response is not valid JSON'
      rescue StandardError => ex
        raise "#{ex.message}: #{@raw_response.inspect}"
      end
    end

    def valid?
      @valid
    end

    def parse(json)
      if json['Message']&.match(/execution error/i)
        @valid = false
        @error = json.dig('Results', 0, 'Message')
        return
      end

      @data = json['Results']
      @error_code = value_id_for('Error Code')&.to_i
      @valid = (@error_code < 4)

      @error = value_for('Error Code') unless valid?
      return unless valid?

      @response = Struct::NhtsaExtendedResponse.new(
        @vin,
        value_for('Make')&.capitalize,
        value_for('Model'),
        value_for('Trim'),
        vehicle_type(value_for('Body Class'), value_for('Vehicle Type')),
        value_for('Model Year'),
        value_for('Body Class'),
        value_for('Vehicle Type'),
        value_for('Doors')&.to_i,
        value_for('Manufacturer Name'),
        value_for('Series'),
        value_for('Trim2'),
        value_for('Series2'),
        value_for('Note'),
        value_for('Gross Vehicle Weight Rating From'),
        value_for('Bed Length (inches)'),
        value_for('Curb Weight (pounds)'),
        value_for('Wheel Base (inches) From'),
        value_for('Wheel Base (inches) To'),
        value_for('Gross Combination Weight Rating From'),
        value_for('Gross Combination Weight Rating To'),
        value_for('Gross Vehicle Weight Rating To'),
        value_for('Bed Type'),
        value_for('Cab Type'),
        value_for('Wheel Size Front (inches)'),
        value_for('Wheel Size Rear (inches)'),
        value_for('Drive Type'),
        value_for('Brake System Type'),
        value_for('Engine Number of Cylinders'),
        value_for('Fuel Type - Primary'),
        value_for('Engine Configuration'),
        value_for('Engine Brake (hp) From'),
        value_for('Engine Manufacturer'),
        value_for('Front Air Bag Locations'),
        value_for('Side Air Bag Locations'),
        value_for('Anti-lock Braking System (ABS)'),
        value_for('Electronic Stability Control (ESC)'),
        value_for('Traction Control'),
        value_for('Tire Pressure Monitoring System (TPMS) Type'),
        value_for('Auto-Reverse System for Windows and Sunroofs'),
        value_for('Keyless Ignition'),
        value_for('Adaptive Cruise Control (ACC)'),
        value_for('Crash Imminent Braking (CIB)'),
        value_for('Forward Collision Warning (FCW)'),
        value_for('Dynamic Brake Support (DBS)'),
        value_for('Blind Spot Warning (BSW)'),
        value_for('Backup Camera'),
        value_for('Rear Cross Traffic Alert'),
        value_for('Rear Automatic Emergency Braking'),
        value_for('Daytime Running Light (DRL)'),
        value_for('Headlamp Light Source'),
        value_for('Semiautomatic Headlamp Beam Switching')
      )
    end

    def vehicle_type(body_class, type)
      case type
      when 'PASSENGER CAR'
        'Car'
      when 'TRUCK'
        body_class =~ /van/i ? 'Van' : 'Truck'
      when 'MULTIPURPOSE PASSENGER VEHICLE (MPV)'
        body_class =~ /Sport Utility/i ? 'SUV' : 'Minivan'
      else
        type
      end
    end

    private

    def get_row(attr_name)
      @data.find { |r| r['Variable'] == attr_name }
    end

    def value_for(attr_name)
      get_row(attr_name)&.[]('Value')
    end

    def value_id_for(attr_name)
      get_row(attr_name)&.[]('ValueId')
    end

    def build_url
      @url = "#{NHTSA_URL}#{@vin}?format=json"
    end

    def fetch
      begin
        @valid = false
        url = URI.parse(@url)
        http_options = { use_ssl: (url.scheme == 'https') }.merge(@http_options)
        Net::HTTP.start(url.host, url.port, http_options) do |http|
          resp = http.request_get(url)
          case resp
          when Net::HTTPSuccess
            @valid = true
            resp.body
          when Net::HTTPRedirection
            raise 'No support for HTTP redirection from NHTSA API'
          when Net::HTTPClientError
            @error = "Client error: #{resp.code} #{resp.message}"
            nil
          else
            @error = resp.message
            nil
          end
        end
      rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, SocketError,
        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
        Net::ProtocolError, Errno::ECONNREFUSED => e
        @error = e.message
        nil
      end
    end
  end

  Struct.new(
    'NhtsaExtendedResponse',
    :vin, :make, :model, :trim, :type, :year, :body_style, :vehicle_class, :doors,
    :manufacturer_name, :series, :trim2, :series2, :note, :gvwr_from, :bed_length,
    :curb_weight, :wheelbase_from, :wheelbase_to, :gcwr_from, :gcwr_to, :gvwr_to,
    :bed_type, :cab_type, :wheel_size_front, :wheel_size_rear, :drive_type,
    :brake_system_type, :engine_cylinders, :fuel_type, :engine_config,
    :engine_hp_from, :engine_manufacturer, :front_airbags, :side_airbags,
    :abs, :esc, :traction_control, :tpms, :auto_reverse,
    :keyless_ignition, :adaptive_cruise, :cib, :fcw, :dbs, :bsw,
    :backup_camera, :rear_cross_traffic, :rear_aeb, :drl, :headlamp_source, :semi_auto_headlamp
  )
end
