syncee
======

Synchronize templates, snippets and global variables from the database of a remote ExpressionEngine site into files on your local file system.

### Dependencies

* Ruby >= 1.9
* SSH

### Usage

1. Ensure Ruby version 1.9 or greater is installed on your local system.
2. Ensure SSH access to the remote host of your ExpressionEngine site.
3. Download `lib/syncee.rb` to somewhere in your local system, eg `~/lib`.
4. Download `example/simple.rb` or `example/multiple.rb` to your local system and edit the required and optional parameters.
5. Depending on where you put the `syncee.rb` library you may also need to edit the `require` path at the top of the script.
6. Run the script.
