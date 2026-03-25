# frozen_string_literal: true

Rails.application.routes.draw do
  get "/",       to: "secrets#index"
  get "/health", to: "secrets#health"
  get "/secrets", to: "secrets#show"
  get "/typed",  to: "secrets#typed"
end
