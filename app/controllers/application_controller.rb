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
      redirect_uri: CGI.escape(oauth_callback_url)
    }

    resp = HTTP
      .basic_auth(:user => client_id, :pass => secret_id)
      .post("#{cognito_url}/oauth2/token", form: data)

    unless resp.status.success?
      puts resp.request.headers
      puts resp.request.body
      return clean_auth_session_and_redirect_to_root(resp.to_s)
    end

    token_info = resp.parse

    resp = HTTP
      .auth("Bearer #{token_info['access_token']}")
      .get("#{cognito_url}/oauth2/userInfo")

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
    callback_url = CGI.escape(root_url)

    redirect_to "#{cognito_url}/logout?client_id=#{client_id}&logout_uri=#{callback_url}", allow_other_host: true
  end

  private

  def clean_auth_session_and_redirect_to_root(notice = nil)
    session.clear
    redirect_to root_path, notice: notice
  end

  def cognito_login_url
    redirect_uri = CGI.escape(oauth_callback_url)

    "#{cognito_url}/oauth2/authorize?client_id=#{client_id}&response_type=code&scope=#{scope}&redirect_uri=#{redirect_uri}"
  end

  def cognito_url
    ENV.fetch('COGNITO_URL')
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
