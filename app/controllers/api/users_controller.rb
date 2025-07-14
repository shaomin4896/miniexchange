class Api::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token
  @@users = {}
  def getAll
    render json: @@users
  end

  def create
    username = params[:username]
    token = SecureRandom.hex(16)
    @@users[token] = username
    render json: { token: token, username: username }
  end
end
