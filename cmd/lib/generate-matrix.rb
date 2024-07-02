# frozen_string_literal: true

require "abstract_command"
require "tap"
require "utils/github/api"
require "cli/parser"
require_relative "ci_matrix"

module Homebrew
  module Cmd
    class GenerateMatrix < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate a GitHub Actions matrix for a given pull request URL or list of cask names.
        EOS

        flag "--url=",
             description: "URL of a pull request to generate a matrix for."
        comma_array "--casks",
                    description: "Comma-separated list of casks to test."
        switch "--skip-install",
               description: "Skip installing casks"
        switch "--new",
               description: "Run new cask checks"
        switch "--syntax-only",
               description: "Only run syntax checks"

        conflicts "--url", "--casks"
        conflicts "--syntax-only", "--url"
        conflicts "--syntax-only", "--casks"
        conflicts "--syntax-only", "--skip-install"
        conflicts "--syntax-only", "--new"
      end

      def run
        skip_install = args.skip_install?
        new_cask = args.new?
        casks = args.casks if args.casks&.any?
        pr_url = args.url

        labels = if pr_url
          pr = GitHub::API.open_rest(pr_url)
          pr.fetch("labels").map { |l| l.fetch("name") }
        else
          []
        end

        tap = Tap.fetch(ENV.fetch("GITHUB_REPOSITORY"))

        runner = CiMatrix.random_runner[:name]
        syntax_job = {
          name:   "syntax",
          tap:    tap.name,
          runner:,
        }

        matrix = [syntax_job]

        if !args.syntax_only? && !labels&.include?("ci-syntax-only")
          cask_jobs = if args.casks&.any?
            CiMatrix.generate(tap, labels:, cask_names: casks, skip_install:, new_cask:)
          else
            CiMatrix.generate(tap, labels:, skip_install:, new_cask:)
          end

          if cask_jobs.any?
            # If casks were changed, skip `audit` for whole tap.
            syntax_job[:skip_audit] = true

            # The syntax job only runs `style` at this point, which should work on Linux.
            # Running on macOS is currently faster though, since `homebrew/cask` and
            # `homebrew/core` are already tapped on macOS CI machines.
            # syntax_job[:runner] = "ubuntu-latest"
          end

          matrix += cask_jobs
        end

        syntax_job[:name] += " (#{syntax_job[:runner]})"

        puts JSON.pretty_generate(matrix)
        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "matrix=#{JSON.generate(matrix)}"
        end
      end
    end
  end
end

Homebrew::Cmd::GenerateMatrix.new.run
