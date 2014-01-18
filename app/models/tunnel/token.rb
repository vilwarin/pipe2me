# A token is an object which allows to create or to extend a tunnel.
module Tunnel::Token
  SELF = self

  TEST_TOKEN = "test@test.kinko.me"
  REVIEW_TOKEN = "review@test.kinko.me"

  def self.included(base)
    base.before_validation :apply_token
    base.validates_presence_of :expires_at
  end

  # Apply the new token
  def apply_token
    return if !new_record? && !token_changed?

    SELF.parse(token).each do |key, value|
      case key
      when :invalid
        errors.add(:token, "Invalid or missing token")
      when :max_ports
        errors.add(:ports, "Too many ports") unless ports.count <= value
      when :extend
        errors.add(:token, "This token is valid for new tunnels only") unless new_record?
      when :period
        self.expires_at = (self.expires_at || Time.now) + value
      end
    end
  end

  private

  def self.parse(token)
    case token
    when TEST_TOKEN
      { :max_ports => 6, :period => 3.minutes, :extend => false }
    when REVIEW_TOKEN
      { :max_ports => 6, :period => 1.day, :extend => false }
    else
      { :invalid => true }
    end
  end

  public

  def online?
    expires_at > Time.now
  end
end

module Tunnel::Token::Etest
  T = Tunnel

  def test_token_is_needed
    assert_raise(ActiveRecord::RecordInvalid) {
      self.tunnel protocols: %w(http), token: nil
    }
  end

  def test_test_token_goes_offline
    require "timecop"

    tunnel = self.tunnel protocols: %w(http)
    assert_equal true, tunnel.online?

    Timecop.travel 5.minutes do
      assert_equal false, tunnel.online?
    end
  end

  def test_token_port_limit
    assert_raise(ActiveRecord::RecordInvalid) {
      self.tunnel protocols: %w(http https tcp tcp), token: nil
    }
  end

  def test_token_update
    require "etest_helper"

    tunnel = self.tunnel protocols: %w(http)
    assert_equal(tunnel.ports.count, 1)

    # updating with TEST_TOKEN does nothing
    tunnel.update_attributes! token: T::TEST_TOKEN

    # updating with REVIEW_TOKEN raises exception
    assert_raise(ActiveRecord::RecordInvalid) {
      tunnel.update_attributes! token: T::REVIEW_TOKEN
    }

    assert_invalid tunnel, :token
  end
end
