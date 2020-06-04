# frozen_string_literal: true

require "service/shared_service_tests"
require "net/http"

if SERVICE_CONFIGURATIONS[:gcs]
  class ActiveStorage::Service::GCSServiceTest < ActiveSupport::TestCase
    SERVICE = ActiveStorage::Service.configure(:gcs, SERVICE_CONFIGURATIONS)

    include ActiveStorage::Service::SharedServiceTests

    test "direct upload" do
      begin
        key      = SecureRandom.base58(24)
        data     = "Something else entirely!"
        checksum = Digest::MD5.base64digest(data)
        url      = @service.url_for_direct_upload(key, expires_in: 5.minutes, content_type: "text/plain", content_length: data.size, checksum: checksum)

        uri = URI.parse url
        request = Net::HTTP::Put.new uri.request_uri
        request.body = data
        request.add_field "Content-Type", ""
        request.add_field "Content-MD5", checksum
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request request
        end

        assert_equal data, @service.download(key)
      ensure
        @service.delete key
      end
    end

    test "upload with content_type and content_disposition" do
      begin
        key      = SecureRandom.base58(24)
        data     = "Something else entirely!"

        @service.upload(key, StringIO.new(data), checksum: Digest::MD5.base64digest(data), disposition: :attachment, filename: ActiveStorage::Filename.new("test.txt"), content_type: "text/plain")

        url = @service.url(key, expires_in: 2.minutes, disposition: :inline, content_type: "text/html", filename: ActiveStorage::Filename.new("test.html"))
        response = Net::HTTP.get_response(URI(url))
        assert_equal "text/plain", response.content_type
        assert_match /attachment;.*test.txt/, response["Content-Disposition"]
      ensure
        @service.delete key
      end
    end

    test "upload with content_type" do
      begin
        key      = SecureRandom.base58(24)
        data     = "Something else entirely!"

        @service.upload(key, StringIO.new(data), checksum: Digest::MD5.base64digest(data), content_type: "text/plain")

        url = @service.url(key, expires_in: 2.minutes, disposition: :inline, content_type: "text/html", filename: ActiveStorage::Filename.new("test.html"))
        response = Net::HTTP.get_response(URI(url))
        assert_equal "text/plain", response.content_type
        assert_match /inline;.*test.html/, response["Content-Disposition"]
      ensure
        @service.delete key
      end
    end

    test "update metadata" do
      begin
        key      = SecureRandom.base58(24)
        data     = "Something else entirely!"
        @service.upload(key, StringIO.new(data), checksum: Digest::MD5.base64digest(data), disposition: :attachment, filename: ActiveStorage::Filename.new("test.html"), content_type: "text/html")

        @service.update_metadata(key, disposition: :inline, filename: ActiveStorage::Filename.new("test.txt"), content_type: "text/plain")
        url = @service.url(key, expires_in: 2.minutes, disposition: :attachment, content_type: "text/html", filename: ActiveStorage::Filename.new("test.html"))

        response = Net::HTTP.get_response(URI(url))
        assert_equal "text/plain", response.content_type
        assert_match /inline;.*test.txt/, response["Content-Disposition"]
      ensure
        @service.delete key
      end
    end

    test "signed URL generation" do
      assert_match(/storage\.googleapis\.com\/.*response-content-disposition=inline.*test\.txt.*response-content-type=text%2Fplain/,
        @service.url(@key, expires_in: 2.minutes, disposition: :inline, filename: ActiveStorage::Filename.new("test.txt"), content_type: "text/plain"))
    end
  end
else
  puts "Skipping GCS Service tests because no GCS configuration was supplied"
end
