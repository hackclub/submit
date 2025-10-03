require 'openssl'
require 'base64'
require 'securerandom'

class StateToken
  # Generate a compact token: payload_b64.nonce.sig_b64
  # payload is a Hash; nonce should be a random string (at least 16 bytes hex)
  def self.generate(payload, nonce: nil)
    raise ArgumentError, 'payload must be a Hash' unless payload.is_a?(Hash)
    nonce ||= SecureRandom.hex(16)
    payload = payload.merge(nonce: nonce)
    payload_b64 = Base64.strict_encode64(payload.to_json)
    sig = sign("#{payload_b64}.#{nonce}")
    sig_b64 = Base64.strict_encode64(sig)
    [payload_b64, nonce, sig_b64].join('.')
  end

  # Verify token and return parsed payload Hash
  def self.verify(token)
    parts = token.to_s.split('.')
    return nil unless parts.length == 3
    payload_b64, nonce, sig_b64 = parts
    expected = sign("#{payload_b64}.#{nonce}")
    got = Base64.decode64(sig_b64) rescue nil
    return nil unless got && secure_compare(expected, got)
    payload_json = Base64.decode64(payload_b64) rescue nil
    return nil unless payload_json
    JSON.parse(payload_json)
  rescue
    nil
  end

  def self.secure_compare(a, b)
    ActiveSupport::SecurityUtils.secure_compare(a, b)
  rescue
    false
  end

  def self.sign(data)
    secret = ENV['STATE_HMAC_SECRET'].presence || Rails.application.secret_key_base
    OpenSSL::HMAC.digest('SHA256', secret, data)
  end
end
