# CRUSH Configuration for Artiste

## Build/Run Commands
- Install dependencies: `bundle install`
- Run server: `ruby app.rb`

## Test Commands
- Run all tests: `bundle exec rspec`
- Run single test file: `bundle exec rspec spec/lib/<file>_spec.rb`
- Run specific test: `bundle exec rspec spec/lib/<file>_spec.rb:<line_number>`

## Linting/Formatting
- Check code style of file: `bundle exec standardrb <file>`
- Check code style of project: `bundle exec rake standardrb`
- Auto-fix style issues: `bundle exec standardrb --fix`

## Code Style Guidelines
- Ruby style follows StandardRB (no semicolons, two-space indentation)
- Use snake_case for variables and methods
- Use CamelCase for classes and modules
- Prefer single quotes for strings unless interpolation is needed
- Use descriptive variable names that convey purpose
- Keep methods short and focused on a single responsibility
- Use keyword arguments for methods with multiple optional parameters

## Import/Require Conventions
- Use `require_relative` for files within the project
- Use `require` for external gems
- Group standard library requires, external gem requires, and internal requires
- Alphabetize within each group

## Error Handling
- Use specific exception classes when rescuing
- Prefer `raise` over `fail` for exception raising
- Include meaningful error messages
- Log errors appropriately for debugging

## Project-Specific Info
- Main entry point: `app.rb`
- Core logic in `lib/`
- Tests in `spec/lib/`
- Database: SQLite (`db/artiste.db`)
- Web framework: Sinatra
- Testing framework: RSpec