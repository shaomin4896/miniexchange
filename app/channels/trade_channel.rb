class TradeChannel < ApplicationCable::Channel
  def subscribed
    stream_from "trades"
  end
end
