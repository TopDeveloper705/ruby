require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      @pwd = Dir.pwd
      @tmpdir = File.join(File.expand_path(Dir.tmpdir), "test_reline_config_#{$$}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      Dir.chdir(@tmpdir)
      @inputrc_backup = ENV['INPUTRC']
      @inputrc_file = ENV['INPUTRC'] = File.join(@tmpdir, 'temporaty_inputrc')
      File.unlink(@inputrc_file) if File.exist?(@inputrc_file)
    end

    def teardown
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
      ENV['INPUTRC'] = @inputrc_backup
      ENV.delete('RELINE_TEST_PROMPT') if ENV['RELINE_TEST_PROMPT']
    end

    def test_history_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n")
      write("\C-p")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :a
        => :a
        prompt> :a
      EOC
    end

    def test_backspace
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":abc\C-h\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :ab
        => :ab
        prompt>
      EOC
    end

    def test_autowrap
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write('01234567890123456789012')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 0123456789012345678901
        2
      EOC
    end

    def test_finish_autowrapped_line
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'a@a', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a@a', 'id'=
        >'ABC'}, 'version'=>4, 'status'=>'succee
        ded'}]
        => [{"user"=>{"email"=>"a@a", "id"=>"ABC
        "}, "version"=>4, "status"=>"succeeded"}
        ]
        prompt>
      EOC
    end

    def test_finish_autowrapped_line_in_the_middle_of_lines
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'abcdef@abcdef', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]#{"\C-b"*7}\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a
        bcdef@abcdef', 'id'=>'ABC'}, '
        version'=>4, 'status'=>'succee
        ded'}]
        => [{"user"=>{"email"=>"abcdef
        @abcdef", "id"=>"ABC"}, "versi
        on"=>4, "status"=>"succeeded"}
        ]
        prompt>
      EOC
    end

    def test_finish_autowrapped_line_in_the_middle_of_multilines
      start_terminal(30, 16, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("<<~EOM\n  ABCDEFG\nEOM\n")
      close
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> <<~EOM
        prompt>   ABCDEF
        G
        prompt> EOM
        => "ABCDEFG\n"
        prompt>
      EOC
    end

    def test_prompt
      write_inputrc <<~'LINES'
        "abc": "123"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("abc\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
    end

    def test_mode_icon_emacs
      write_inputrc <<~LINES
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        @prompt>
      EOC
    end

    def test_mode_icon_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        (ins)prompt> :a
        => :a
        (cmd)prompt> :a
      EOC
    end

    def test_original_mode_icon_emacs
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string [emacs]
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
    end

    def test_original_mode_icon_with_quote
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string "[emacs]"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
    end

    def test_original_mode_icon_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
        set vi-ins-mode-string "{InS}"
        set vi-cmd-mode-string "{CmD}"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        {InS}prompt> :a
        => :a
        {CmD}prompt> :a
      EOC
    end

    def test_prompt_with_escape_sequence
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("123\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
    end

    def test_prompt_with_escape_sequence_and_autowrap
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("12345678\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 1234567
        8
        => 12345678
        prompt>
      EOC
    end

    def test_multiline_and_autowrap
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaa\n  33333333\n        end\C-a\C-pputs\C-e\e\C-m88888888888")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def aaa
        aaa
        prompt> puts  3
        3333333
        prompt> 8888888
        8888
        prompt>
         end
      EOC
    end

    def test_clear
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("3\C-l")
      close
      assert_screen(<<~EOC)
        prompt> 3
      EOC
    end

    def test_clear_multiline_and_autowrap
      omit # FIXME clear logic is buggy
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaa\n  3\n\C-lend")
      close
      assert_screen(<<~EOC)
        prompt> def aaa
        aaa
        prompt>   3
        prompt> end
      EOC
    end

    def test_nearest_cursor
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def ああ\n  :いい\nend\C-pbb\C-pcc")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def ccああ
        prompt>   :bbいい
        prompt> end
      EOC
    end

    def test_delete_line
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n\nend\C-p\C-h")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def a
        prompt> end
      EOC
    end

    def test_last_line_of_screen
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\n\n\n\n\ndef a\nend")
      close
      assert_screen(<<~EOC)
        prompt>
        prompt>
        prompt>
        prompt> def a
        prompt> end
      EOC
    end

    # c17a09b7454352e2aff5a7d8722e80afb73e454b
    def test_autowrap_at_last_line_of_screen
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\nend\n\C-p")
      close
      assert_screen(<<~EOC)
        prompt> def a
        prompt> end
        => :a
        prompt> def a
        prompt> end
      EOC
    end

    # f002483b27cdb325c5edf9e0fe4fa4e1c71c4b0e
    def test_insert_line_in_the_middle_of_line
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("333\C-b\C-b\e\C-m8")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 3
        prompt> 833
      EOC
    end

    # 9d8978961c5de5064f949d56d7e0286df9e18f43
    def test_insert_line_in_the_middle_of_line_at_last_line_of_screen
      start_terminal(3, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("3333333333\C-a\C-f\e\C-m")
      close
      assert_screen(<<~EOC)
        prompt> 3
        prompt> 3333333
        33
      EOC
    end

    def test_insert_after_clear
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  01234\nend\C-l\C-p5678")
      close
      assert_screen(<<~EOC)
        prompt> def a
        prompt>   056781234
        prompt> end
      EOC
    end

    def test_multiline_incremental_search
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  8\nend\ndef b\n  3\nend\C-s8")
      close
      assert_screen(<<~EOC)
        (i-search)`8'def a
        (i-search)`8'  8
        (i-search)`8'end
      EOC
    end

    private def write_inputrc(content)
      File.open(@inputrc_file, 'w') do |f|
        f.write content
      end
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
