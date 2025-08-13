RcrewAI::Rails::Engine.routes.draw do
  root to: "crews#index"

  resources :crews do
    member do
      post :execute
    end
    resources :agents
    resources :tasks
  end

  resources :executions, only: [:index, :show] do
    member do
      post :cancel
      get :logs
    end
  end

  resources :agents do
    resources :tools
  end

  resources :tasks do
    member do
      post :add_dependency
      delete :remove_dependency
    end
  end

  # API endpoints
  namespace :api do
    namespace :v1 do
      resources :crews, only: [:index, :show, :create] do
        member do
          post :execute
        end
      end
      
      resources :executions, only: [:index, :show] do
        member do
          get :status
          get :logs
        end
      end
    end
  end

  # Mount Turbo Streams for real-time updates
  mount ActionCable.server => '/cable' if defined?(ActionCable)
end