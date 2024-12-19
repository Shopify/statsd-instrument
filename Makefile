.PHONY: test lint update
test:
	bundle exec rake test

lint:
	bundle exec rake lint_fix

update:
	bundle update

check: update lint test