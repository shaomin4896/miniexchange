require "rbtree"
require "bigdecimal"
require "bigdecimal/util"

class Api::OrdersController < ApplicationController
  skip_before_action :verify_authenticity_token

  # 價格排序樹
  @@buy_tree = RBTree.new { |a, b| b <=> a }   # 高價優先
  @@sell_tree = RBTree.new { |a, b| a <=> b }  # 低價優先
  @@trades = []

  def create
    token = params[:token]
    unless Api::UsersController.class_variable_get(:@@users).key?(token)
      return render json: { error: "Invalid user token" }, status: :unauthorized
    end

    side = params[:side]
    price = BigDecimal(params[:price].to_s)
    quantity = BigDecimal(params[:quantity].to_s)

    match(token, side, price, quantity)

    render json: { message: "Order received" }
  end

  def getFill
    token = params[:token]
    users = Api::UsersController.class_variable_get(:@@users)
    user = users[token]

    return render json: { error: "Invalid token" }, status: :unauthorized unless user

    my_trades = @@trades.select { |t| t[:buyer] == user || t[:seller] == user }

    render json: my_trades.map { |t|
      {
        price: t[:price].to_s("F"),
        quantity: t[:quantity].to_s("F"),
        buyer: t[:buyer],
        seller: t[:seller],
        time: t[:time]
      }
    }
  end

  def book
    buy_orders = @@buy_tree.flat_map do |price, orders|
      orders.map do |o|
        {
          side: "buy",
          price: price.to_s("F"),
          quantity: o[:quantity].to_s("F"),
          user: o[:user]
        }
      end
    end

    sell_orders = @@sell_tree.flat_map do |price, orders|
      orders.map do |o|
        {
          side: "sell",
          price: price.to_s("F"),
          quantity: o[:quantity].to_s("F"),
          user: o[:user]
        }
      end
    end

    render json: { buy: buy_orders, sell: sell_orders }
  end

  private

  def match(token, side, price, quantity)
    users = Api::UsersController.class_variable_get(:@@users)
    user = users[token]

    if side == "buy"
      # 撮合：買方吃賣方
      while quantity > 0 && @@sell_tree.any? && @@sell_tree.first[0] <= price
        sell_price, sell_orders = @@sell_tree.first
        sell_order = sell_orders.shift

        trade_qty = [ quantity, sell_order[:quantity] ].min
        quantity -= trade_qty
        sell_order[:quantity] -= trade_qty

        @@trades << {
          price: sell_price,
          quantity: trade_qty,
          buyer: user,
          seller: sell_order[:user],
          time: Time.now
        }
        ActionCable.server.broadcast("trades", @@trades.last)

        # 還有剩的賣單補回陣列頭
        sell_orders.unshift(sell_order) if sell_order[:quantity] > 0
        @@sell_tree.delete(sell_price) if sell_orders.empty?
      end

      # 剩下的買單掛單
      if quantity > 0
        @@buy_tree[price] ||= []
        @@buy_tree[price] << { quantity: quantity, user: user }
      end
    else
      # 撮合：賣方吃買方
      while quantity > 0 && @@buy_tree.any? && @@buy_tree.first[0] >= price
        buy_price, buy_orders = @@buy_tree.first
        buy_order = buy_orders.shift

        trade_qty = [ quantity, buy_order[:quantity] ].min
        quantity -= trade_qty
        buy_order[:quantity] -= trade_qty

        @@trades << {
          price: buy_price,
          quantity: trade_qty,
          buyer: buy_order[:user],
          seller: user,
          time: Time.now
        }
        ActionCable.server.broadcast("trades", @@trades.last)

        buy_orders.unshift(buy_order) if buy_order[:quantity] > 0
        @@buy_tree.delete(buy_price) if buy_orders.empty?
      end

      # 剩下的賣單掛單
      if quantity > 0
        @@sell_tree[price] ||= []
        @@sell_tree[price] << { quantity: quantity, user: user }
      end
    end
  end
end
