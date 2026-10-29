# frozen_string_literal: true

target :hawk do
  configure_code_diagnostics do |diagnostics|
    diagnostics[Steep::Diagnostic::Ruby::UndeclaredMethodDefinition] = :error
    diagnostics[Steep::Diagnostic::Ruby::SyntaxError] = :error
    diagnostics[Steep::Diagnostic::Ruby::UnexpectedError] = :error
  end
  check "lib"
  signature "sig"
  library "base64"
  library "json"
  library "uri"
  library "open3"
  library "securerandom"
  library "net-http"
  library "timeout"
  library "time"
  library "logger"
end
