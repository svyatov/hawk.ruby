# Contributing

Hawk Ruby accepts bug reports, documentation improvements, and code contributions through [GitHub](https://github.com/svyatov/hawk.ruby).

## Set up

Install CRuby 3.3 or later and the Bundler version recorded in `Gemfile.lock`. Fork the repository, clone your fork, and install its dependencies:

```sh
bundle install
```

Integration tests also need the bundles under `gemfiles/`. Install each bundle you need, for example:

```sh
bundle install --gemfile gemfiles/rails_8_1.gemfile
```

The complete coverage run needs all 12 integration bundles. Resque tests need a `redis-server` executable.

## Check a change

Run the fast checks from the repository root:

```sh
bundle exec rake check:fast
```

Run coverage, coverage-backed complexity, dependency scanning, and installed-package checks before submitting runtime changes:

```sh
bundle exec rake check:coverage
bundle exec rake check:crap
bundle exec rake check:audit
bundle exec rake test:package
```

[Verification](docs/verification.md) defines the acceptance requirements and explains these checks. CI runs the same checks across the supported Ruby versions and integration bundles.

Every change that adds functionality must include a test. A bug fix should include a regression test. Keep changes focused and preserve unrelated behavior.

## Submit a pull request

Create a branch named `type/short-description`, such as `fix/rack-capture`. Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for commit subjects.

Push the branch to your fork and open a pull request against `main`. Explain the problem, the resulting behavior, and any evidence that automated checks cannot provide.

Pull requests use squash merging. Discuss changes to the public API or supported integrations before implementing them.

## Decisions and continuity

Leonid Svyatov is the sole maintainer and decides which changes to merge and release. No succession arrangement exists if he stops maintaining the project.

## Reports and conduct

Use [GitHub issues](https://github.com/svyatov/hawk.ruby/issues) for questions and defects. Follow the [code of conduct](CODE_OF_CONDUCT.md).

Report vulnerabilities through the private channel in [SECURITY.md](SECURITY.md).
