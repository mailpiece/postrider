SYSTEM_TEST_ENV = "PARALLEL_WORKERS=1" # system tests can't run reliably in parallel

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Gemfile: Drift check", "bash -c 'diff <(bundle lock --print) Gemfile.lock'"
  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Security: Gitleaks audit", "bin/gitleaks-audit"
  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "env #{SYSTEM_TEST_ENV} bin/rails test:system"

  if success?
    step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  else
    failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  end
end
