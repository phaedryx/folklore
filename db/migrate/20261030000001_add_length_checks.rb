# Caps the caller-supplied strings that had no limit. Names, dirs and tag
# names are btree index keys: past ~2.7 KB an insert failed with "index row
# size exceeds maximum" and the caller saw "Internal error". The task outcome
# note is not indexed but is copied into event metadata. The mutations check
# the same limits first (Asset::MAX_*_LENGTH, Tag::MAX_NAME_LENGTH,
# Task::MAX_NOTE_LENGTH) so a caller gets a message naming the limit.
class AddLengthChecks < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :assets, "char_length(name) <= 255", name: "assets_name_length_check"
    add_check_constraint :assets, "char_length(dir) <= 1024", name: "assets_dir_length_check"
    add_check_constraint :tags, "char_length(name) <= 100", name: "tags_name_length_check"
    add_check_constraint :tasks, "char_length(outcome_note) <= 10000", name: "tasks_outcome_note_length_check"
  end
end
