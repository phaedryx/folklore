require "diff/lcs"

module Versions
  # Side-by-side line diff between two text snapshots, computed with diff-lcs.
  # Each row is an aligned [old_cell, new_cell] pair from Diff::LCS.sdiff.
  class DiffComponent < ViewComponent::Base
    Cell = Data.define(:text, :state) do
      def present? = state != "empty"
    end

    def initialize(old_content:, new_content:)
      @old_lines = old_content.to_s.split("\n", -1)
      @new_lines = new_content.to_s.split("\n", -1)
    end

    def rows
      @rows ||= Diff::LCS.sdiff(@old_lines, @new_lines).map do |change|
        [ old_cell(change), new_cell(change) ]
      end
    end

    def css_for(cell)
      cell.state == "empty" ? "diff-empty" : "diff-line diff-#{cell.state}"
    end

    private

    def old_cell(change)
      case change.action
      when "=" then Cell.new(text: change.old_element, state: "unchanged")
      when "!", "-" then Cell.new(text: change.old_element, state: "removed")
      else Cell.new(text: nil, state: "empty")
      end
    end

    def new_cell(change)
      case change.action
      when "=" then Cell.new(text: change.new_element, state: "unchanged")
      when "!", "+" then Cell.new(text: change.new_element, state: "added")
      else Cell.new(text: nil, state: "empty")
      end
    end
  end
end
