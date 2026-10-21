module FixtureUuidTestHelper
  extend ActiveSupport::Concern

  class_methods do
    def identify(label, column_type = :integer)
      if label.to_s.end_with?("_uuid")
        column_type = :uuid
        label = label.to_s.delete_suffix("_uuid")
      end

      # Rails passes :string for varchar columns, so handle both :uuid and :string
      return super(label, column_type) unless column_type.in?([ :uuid, :string ])
      generate_fixture_uuid(label)
    end

    private

    def generate_fixture_uuid(label)
      # Deterministic UUIDv7 from Rails' CRC32 fixture ID order, timestamped in the past
      # so fixtures always sort older than records created during the test.
      fixture_int = Zlib.crc32("fixtures/#{label}") % (2**30 - 1)

      base_time = Time.utc(2024, 1, 1, 0, 0, 0)
      timestamp = base_time + (fixture_int / 1000.0)

      uuid_v7_with_timestamp(timestamp, label)
    end

    def uuid_v7_with_timestamp(time, seed_string)
      time_ms = time.to_f * 1000
      timestamp_ms = time_ms.to_i

      bytes = []
      bytes[0] = (timestamp_ms >> 40) & 0xff
      bytes[1] = (timestamp_ms >> 32) & 0xff
      bytes[2] = (timestamp_ms >> 24) & 0xff
      bytes[3] = (timestamp_ms >> 16) & 0xff
      bytes[4] = (timestamp_ms >> 8) & 0xff
      bytes[5] = timestamp_ms & 0xff

      frac_ms = time_ms - timestamp_ms
      sub_ms_precision = (frac_ms * 4096).to_i & 0xfff

      hash = Digest::MD5.hexdigest(seed_string)

      bytes[6] = ((sub_ms_precision >> 8) & 0x0f) | 0x70  # version 7
      bytes[7] = sub_ms_precision & 0xff

      rand_b = hash[3...19].to_i(16) & ((2**62) - 1)
      bytes[8] = ((rand_b >> 56) & 0x3f) | 0x80  # variant 10
      bytes[9] = (rand_b >> 48) & 0xff
      bytes[10] = (rand_b >> 40) & 0xff
      bytes[11] = (rand_b >> 32) & 0xff
      bytes[12] = (rand_b >> 24) & 0xff
      bytes[13] = (rand_b >> 16) & 0xff
      bytes[14] = (rand_b >> 8) & 0xff
      bytes[15] = rand_b & 0xff

      uuid = "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % bytes
      ActiveRecord::Type::Uuid.hex_to_base36(uuid.delete("-"))
    end
  end
end
