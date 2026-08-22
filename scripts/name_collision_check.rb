# frozen_string_literal: true
#
# Throwaway script: estimates how many auto-generated sign-up usernames can be
# created before the first collision. Not part of the application -- it lived in
# app/controllers/auth/ and ran a loop at load time, which is a hazard under
# production eager-loading. Run with: bundle exec ruby scripts/name_collision_check.rb

require 'random_name_generator'
require 'set'

class NameGenerator

  @@first_name_generator = RandomNameGenerator.new(File.new("#{File.expand_path('../app/controllers/auth', __dir__)}/roman.txt"))
  @@last_name_generator = RandomNameGenerator.new(RandomNameGenerator::FANTASY)

  def generate_name
    "#{@@first_name_generator.compose(3)} #{@@last_name_generator.compose(3)}"
  end
end

generator = NameGenerator.new

names = Set.new

while true do
  name = generator.generate_name
  puts "name: #{name}"

  if !names.add?(name)
    puts "collision after #{names.size} names"
    break
  end

  names.add(name)
end
