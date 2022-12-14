class ApplicationController < ActionController::Base
  def authenticate_user!
    unless current_user
      redirect_to cognito_login_url, allow_other_host: true
    end
  end

  def current_user
    @current_user ||= User.find(session[:current_user_id]) if session[:current_user_id].present?
  end

  def callback
    code = params[:code]

    return clean_auth_session_and_redirect_to_root if code.blank?

    data = {
      grant_type: 'authorization_code',
      client_id: client_id,
      code: code,
      redirect_uri: oauth_callback_url
    }

    resp = HTTP
      .basic_auth(user: client_id, pass: secret_id)
      .post(cognito_url('/oauth2/token'), form: data)

    return clean_auth_session_and_redirect_to_root(resp.to_s) unless resp.status.success?

    token_info = resp.parse

    resp = HTTP
      .auth("Bearer #{token_info['access_token']}")
      .get(cognito_url('/oauth2/userInfo'))

    return clean_auth_session_and_redirect_to_root(resp.to_s) unless resp.status.success?

    user_info = resp.parse

    user = User.find_or_create_by(sub: user_info['sub'])
    user.update!(user_info.merge(token_info: token_info.to_json))

    session[:current_user_id] = user.id

    redirect_to points_path, notice: 'Login realizado com sucesso!'
  end

  def logout
    current_user&.update(token_info: nil)
    session.clear
    redirect_to cognito_logout_url, allow_other_host: true
  end

  private

  def clean_auth_session_and_redirect_to_root(notice = nil)
    session.clear
    redirect_to root_path, notice: notice
  end

  def cognito_login_url
    cognito_url('/oauth2/authorize', {
      client_id: client_id,
      response_type: 'code',
      scope: scope,
      redirect_uri: oauth_callback_url
    })
  end

  def cognito_logout_url
    cognito_url('/logout', client_id: client_id, logout_uri: root_url)
  end

  def cognito_url(path = '/', params = {})
    path = "/#{path}" unless path.start_with?('/')
    url = "#{ENV.fetch('COGNITO_URL')}#{path}"
    url += "?#{params.to_query}" if params.to_query.present?
    url
  end

  def client_id
    ENV.fetch('COGNITO_CLIENT_ID')
  end

  def secret_id
    ENV.fetch('COGNITO_CLIENT_SECRET')
  end

  def scope
    ENV.fetch('COGNITO_SCOPE')
  end
end
