# frozen_string_literal: true

module Teek
  class Debugger
    # Prefix for all debugger widget paths
    TOP = ".teek_debug"
    NB  = "#{TOP}.nb"
    WATCH_HISTORY_SIZE = 50

    attr_reader :interp

    def initialize(app)
      @app = app
      @interp = app.interp
      @watches = {}

      app.command(:toplevel, TOP)
      app.command(:wm, 'title', TOP, 'Teek Debugger')
      app.command(:wm, 'geometry', TOP, '400x500')

      # Don't let closing the debugger kill the app
      close_proc = proc { |*| app.command(:wm, 'withdraw', TOP) }
      app.command(:wm, 'protocol', TOP, 'WM_DELETE_WINDOW', close_proc)

      setup_ui
      sync_widget_tree
      start_auto_refresh

      # Start behind the main app window
      app.command(:lower, TOP, '.')
    end

    def show
      @app.command(:wm, 'deiconify', TOP)
      @app.command(:raise, TOP)
    end

    def hide
      @app.command(:wm, 'withdraw', TOP)
    end

    # Called by App when a widget is created
    def on_widget_created(path, cls)
      tree = "#{NB}.widgets.tree"
      return unless @app.command(:winfo, 'exists', tree) == "1"
      return if @app.command(tree, 'exists', path) == "1"

      ensure_parent_exists(path)
      parent_id = parent_tree_id(path)
      name = tk_basename(path)

      @app.command(tree, 'insert', parent_id, 'end',
        id: path, text: name, values: Teek.make_list(path, cls))
      @app.command(tree, 'item', parent_id, open: 1)
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: on_widget_created(#{path}): #{e.message}"
    end

    # Called by App when a widget is destroyed
    def on_widget_destroyed(path)
      tree = "#{NB}.widgets.tree"
      return unless @app.command(:winfo, 'exists', tree) == "1"
      return unless @app.command(tree, 'exists', path) == "1"

      @app.command(tree, 'delete', path)
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: on_widget_destroyed(#{path}): #{e.message}"
    end

    private

    def setup_ui
      @app.command('ttk::notebook', NB)
      @app.command(:pack, NB, fill: :both, expand: 1)

      setup_widget_tree_tab
      setup_variables_tab
      setup_watches_tab
    end

    # ── Widgets tab ──────────────────────────────────────────

    def setup_widget_tree_tab
      tree = "#{NB}.widgets.tree"

      @app.command('ttk::frame', "#{NB}.widgets")
      @app.command(NB, 'add', "#{NB}.widgets", text: 'Widgets')

      @app.command('ttk::treeview', tree,
        columns: 'path class', show: 'tree headings', selectmode: :browse)
      @app.command(tree, 'heading', '#0', text: 'Name')
      @app.command(tree, 'heading', 'path', text: 'Path')
      @app.command(tree, 'heading', 'class', text: 'Class')
      @app.command(tree, 'column', '#0', width: 150)
      @app.command(tree, 'column', 'path', width: 150)
      @app.command(tree, 'column', 'class', width: 100)

      @app.command('ttk::scrollbar', "#{NB}.widgets.vsb",
        orient: :vertical, command: "#{tree} yview")
      @app.command(tree, 'configure', yscrollcommand: "#{NB}.widgets.vsb set")

      @app.command(:pack, "#{NB}.widgets.vsb", side: :right, fill: :y)
      @app.command(:pack, tree, fill: :both, expand: 1)

      # Root item for "."
      @app.command(tree, 'insert', '', 'end',
        id: '.', text: '.', values: '. Tk', open: 1)

      setup_detail_panel
    end

    def setup_detail_panel
      tree = "#{NB}.widgets.tree"
      detail = "#{NB}.widgets.detail"
      detail_text = "#{detail}.text"

      @app.command('ttk::frame', detail)
      @app.command(:pack, detail, side: :bottom, fill: :x)
      @app.command(:text, detail_text,
        height: 6, wrap: :word, state: :disabled, font: 'TkFixedFont')
      @app.command(:pack, detail_text, fill: :x)

      # Repack tree to not overlap detail
      @app.command(:pack, detail, before: tree, side: :bottom, fill: :x)

      select_proc = proc { |*| on_tree_select }
      @app.command(tree, 'configure', cursor: 'hand2')
      @app.command(:bind, tree, '<<TreeviewSelect>>', select_proc)
    end

    def on_tree_select
      tree = "#{NB}.widgets.tree"
      detail_text = "#{NB}.widgets.detail.text"

      sel = @app.command(tree, 'selection')
      return if sel.empty?

      path = sel
      begin
        config = @app.command(path, 'configure')
        lines = Teek.split_list(config).map { |item|
          parts = Teek.split_list(item)
          next if parts.size < 5
          "  #{parts[0]} = #{parts[4]}"
        }.compact.join("\n")
        detail = "#{path}\n#{lines}"
      rescue Teek::TclError
        detail = "#{path}\n  (widget no longer exists)"
      end

      @app.command(detail_text, 'configure', state: :normal)
      @app.command(detail_text, 'delete', '1.0', 'end')
      @app.command(detail_text, 'insert', '1.0', detail)
      @app.command(detail_text, 'configure', state: :disabled)
    end

    # ── Variables tab ────────────────────────────────────────

    def setup_variables_tab
      vars_tree = "#{NB}.vars.tree"

      @app.command('ttk::frame', "#{NB}.vars")
      @app.command(NB, 'add', "#{NB}.vars", text: 'Variables')

      # Toolbar: search entry + refresh button
      @app.command('ttk::frame', "#{NB}.vars.toolbar")
      @app.command(:pack, "#{NB}.vars.toolbar", fill: :x, padx: 2, pady: 2)

      @app.command('ttk::label', "#{NB}.vars.toolbar.lbl", text: 'Filter:')
      @app.command(:pack, "#{NB}.vars.toolbar.lbl", side: :left)

      @app.command('ttk::entry', "#{NB}.vars.toolbar.search")
      @app.command(:pack, "#{NB}.vars.toolbar.search",
        side: :left, fill: :x, expand: 1, padx: 4)

      refresh_proc = proc { |*| refresh_variables }
      @app.command('ttk::button', "#{NB}.vars.toolbar.refresh",
        text: 'Refresh', command: refresh_proc)
      @app.command(:pack, "#{NB}.vars.toolbar.refresh", side: :right)

      # Filter on keypress
      filter_proc = proc { |*| filter_variables }
      @app.command(:bind, "#{NB}.vars.toolbar.search", '<KeyRelease>', filter_proc)

      # Treeview: name, value, type
      @app.command('ttk::treeview', vars_tree,
        columns: 'value type', show: 'tree headings', selectmode: :browse)
      @app.command(vars_tree, 'heading', '#0', text: 'Name')
      @app.command(vars_tree, 'heading', 'value', text: 'Value')
      @app.command(vars_tree, 'heading', 'type', text: 'Type')
      @app.command(vars_tree, 'column', '#0', width: 150)
      @app.command(vars_tree, 'column', 'value', width: 200)
      @app.command(vars_tree, 'column', 'type', width: 50)

      @app.command('ttk::scrollbar', "#{NB}.vars.vsb",
        orient: :vertical, command: "#{vars_tree} yview")
      @app.command(vars_tree, 'configure',
        yscrollcommand: "#{NB}.vars.vsb set")

      @app.command(:pack, "#{NB}.vars.vsb", side: :right, fill: :y)
      @app.command(:pack, vars_tree, fill: :both, expand: 1)

      # Right-click context menu
      @app.command(:menu, "#{NB}.vars.ctx", tearoff: 0)
      watch_proc = proc { |*| watch_selected_variable }
      @app.command("#{NB}.vars.ctx", 'add', 'command',
        label: 'Watch', command: watch_proc)

      @app.command(:bind, vars_tree, '<Button-3>', proc { |*|
        # Select the row under cursor, then show context menu
        @app.tcl_eval("
          set item [#{vars_tree} identify item [winfo pointerx #{vars_tree}] [winfo pointery #{vars_tree}]]
          if {$item ne {}} { #{vars_tree} selection set $item }
        ")
        @app.tcl_eval("tk_popup #{NB}.vars.ctx [winfo pointerx .] [winfo pointery .]")
      })

      # Double-click to watch
      @app.command(:bind, vars_tree, '<Double-1>', proc { |*| watch_selected_variable })

      refresh_variables
    end

    def refresh_variables
      new_data = fetch_variables
      return if new_data == @var_data

      vars_tree = "#{NB}.vars.tree"

      # Preserve selection and scroll
      sel = @app.command(vars_tree, 'selection') rescue ""
      scroll = Teek.split_list(@app.command(vars_tree, 'yview')) rescue nil

      @var_data = new_data
      filter_variables

      # Restore selection if item still exists
      unless sel.empty?
        if @app.command(vars_tree, 'exists', sel) == "1"
          @app.command(vars_tree, 'selection', 'set', sel)
        end
      end

      # Restore scroll position
      if scroll && scroll.size == 2
        @app.command(vars_tree, 'yview', 'moveto', scroll[0])
      end
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: refresh_variables: #{e.message}"
    end

    def fetch_variables
      vars = {}
      names = Teek.split_list(@app.command(:info, 'globals'))
      names.sort.each do |name|
        is_array = @app.command(:array, 'exists', name) == "1"
        if is_array
          begin
            elements = Teek.split_list(@app.command(:array, 'get', name))
            pairs = elements.each_slice(2).to_a
            vars[name] = { type: "array", value: "(#{pairs.size} elements)", elements: pairs }
          rescue Teek::TclError
            vars[name] = { type: "array", value: "(error reading)" }
          end
        else
          begin
            val = @app.command(:set, name)
            vars[name] = { type: "scalar", value: val }
          rescue Teek::TclError
            vars[name] = { type: "?", value: "(error reading)" }
          end
        end
      end
      vars
    end

    def filter_variables
      return unless @var_data

      vars_tree = "#{NB}.vars.tree"
      pattern = @app.command("#{NB}.vars.toolbar.search", 'get').downcase

      # Clear tree — uses Tcl command substitution
      @app.tcl_eval("#{vars_tree} delete [#{vars_tree} children {}]")

      @var_data.each do |name, info|
        next unless pattern.empty? ||
          name.downcase.include?(pattern) ||
          info[:value].downcase.include?(pattern)

        display_val = info[:value]
        display_val = display_val[0, 200] + "..." if display_val.size > 200

        item_id = "v:#{name}"
        @app.command(vars_tree, 'insert', '', 'end',
          id: item_id, text: name,
          values: Teek.make_list(display_val, info[:type]))

        # For arrays, add child items for each element
        next unless info[:type] == "array" && info[:elements]
        info[:elements].each do |key, val|
          next unless pattern.empty? ||
            key.downcase.include?(pattern) ||
            val.downcase.include?(pattern)
          el_val = val.size > 200 ? val[0, 200] + "..." : val
          @app.command(vars_tree, 'insert', item_id, 'end',
            id: "v:#{name}:#{key}", text: "#{name}(#{key})",
            values: Teek.make_list(el_val, ''))
        end
      end
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: filter_variables: #{e.message}"
    end

    def update_variables_incremental
      return unless @var_data

      vars_tree = "#{NB}.vars.tree"
      pattern = @app.command("#{NB}.vars.toolbar.search", 'get').downcase

      # Build set of vars that match the current filter
      visible = {}
      @var_data.each do |name, info|
        next unless pattern.empty? ||
          name.downcase.include?(pattern) ||
          info[:value].downcase.include?(pattern)
        visible[name] = info
      end

      # Walk current tree items: update existing, mark deleted
      current_ids = Teek.split_list(@app.command(vars_tree, 'children', ''))
      in_tree = {}

      current_ids.each do |item_id|
        name = item_id.sub(/\Av:/, '')
        in_tree[name] = item_id

        if visible.key?(name)
          info = visible[name]
          display_val = info[:value]
          display_val = display_val[0, 200] + "..." if display_val.size > 200

          @app.command(vars_tree, 'item', item_id,
            text: name,
            values: Teek.make_list(display_val, info[:type]))

          if info[:type] == "array" && info[:elements]
            update_array_children(vars_tree, item_id, name, info[:elements], pattern)
          else
            # Remove leftover children (e.g. was array, now scalar)
            children = Teek.split_list(@app.command(vars_tree, 'children', item_id))
            children.each { |c| @app.command(vars_tree, 'delete', c) } unless children.empty?
          end
        else
          # Mark as deleted in-place
          current_text = @app.command(vars_tree, 'item', item_id, '-text')
          unless current_text.include?("(deleted)")
            @app.command(vars_tree, 'item', item_id,
              text: "(deleted) #{name}",
              values: Teek.make_list("", ""))
            children = Teek.split_list(@app.command(vars_tree, 'children', item_id))
            children.each { |c| @app.command(vars_tree, 'delete', c) }
          end
        end
      end

      # Append new vars not yet in tree
      visible.each do |name, info|
        next if in_tree.key?(name)

        display_val = info[:value]
        display_val = display_val[0, 200] + "..." if display_val.size > 200

        item_id = "v:#{name}"
        @app.command(vars_tree, 'insert', '', 'end',
          id: item_id, text: name,
          values: Teek.make_list(display_val, info[:type]))

        next unless info[:type] == "array" && info[:elements]
        info[:elements].each do |key, val|
          next unless pattern.empty? ||
            key.downcase.include?(pattern) ||
            val.downcase.include?(pattern)
          el_val = val.size > 200 ? val[0, 200] + "..." : val
          @app.command(vars_tree, 'insert', item_id, 'end',
            id: "v:#{name}:#{key}", text: "#{name}(#{key})",
            values: Teek.make_list(el_val, ''))
        end
      end
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: update_variables_incremental: #{e.message}"
    end

    def update_array_children(vars_tree, parent_id, name, elements, pattern)
      current_children = Teek.split_list(@app.command(vars_tree, 'children', parent_id))
      child_set = {}
      current_children.each { |c| child_set[c] = true }

      seen = {}
      elements.each do |key, val|
        next unless pattern.empty? ||
          key.downcase.include?(pattern) ||
          val.downcase.include?(pattern)

        el_id = "v:#{name}:#{key}"
        el_val = val.size > 200 ? val[0, 200] + "..." : val
        seen[el_id] = true

        if child_set.key?(el_id)
          @app.command(vars_tree, 'item', el_id,
            text: "#{name}(#{key})",
            values: Teek.make_list(el_val, ''))
        else
          @app.command(vars_tree, 'insert', parent_id, 'end',
            id: el_id, text: "#{name}(#{key})",
            values: Teek.make_list(el_val, ''))
        end
      end

      # Remove children no longer in the array
      (child_set.keys - seen.keys).each do |old_id|
        @app.command(vars_tree, 'delete', old_id)
      end
    end

    def watch_selected_variable
      vars_tree = "#{NB}.vars.tree"
      sel = @app.command(vars_tree, 'selection')
      return if sel.empty?

      name = @app.command(vars_tree, 'item', sel, '-text')
      return if name.empty?

      # Strip array(key) back to just the array name
      name = name.sub(/\(.*\)\z/, '')
      add_watch(name)
    end

    # ── Watches tab ──────────────────────────────────────────

    def setup_watches_tab
      watch_tree = "#{NB}.watches.tree"

      @app.command('ttk::frame', "#{NB}.watches")
      @app.command(NB, 'add', "#{NB}.watches", text: 'Watches')

      # Toolbar: refresh button
      @app.command('ttk::frame', "#{NB}.watches.toolbar")
      @app.command(:pack, "#{NB}.watches.toolbar", fill: :x, padx: 2, pady: 2)

      refresh_proc = proc { |*| refresh_watches }
      @app.command('ttk::button', "#{NB}.watches.toolbar.refresh",
        text: 'Refresh', command: refresh_proc)
      @app.command(:pack, "#{NB}.watches.toolbar.refresh", side: :right)

      # Help label — shown when no watches exist
      @app.command('ttk::label', "#{NB}.watches.help",
        text: "Right-click a variable in the Variables tab to watch it.",
        foreground: 'gray50')
      @app.command(:pack, "#{NB}.watches.help", expand: 1)

      # Treeview: name, current value, changes count
      @app.command('ttk::treeview', watch_tree,
        columns: 'value changes', show: 'tree headings', selectmode: :browse)
      @app.command(watch_tree, 'heading', '#0', text: 'Name')
      @app.command(watch_tree, 'heading', 'value', text: 'Value')
      @app.command(watch_tree, 'heading', 'changes', text: 'Changes')
      @app.command(watch_tree, 'column', '#0', width: 120)
      @app.command(watch_tree, 'column', 'value', width: 200)
      @app.command(watch_tree, 'column', 'changes', width: 60)

      @app.command('ttk::scrollbar', "#{NB}.watches.vsb",
        orient: :vertical, command: "#{watch_tree} yview")
      @app.command(watch_tree, 'configure',
        yscrollcommand: "#{NB}.watches.vsb set")

      # Don't pack tree yet — help label is shown first

      # Detail panel for history
      @app.command(:text, "#{NB}.watches.history",
        height: 8, wrap: :word, state: :disabled, font: 'TkFixedFont')

      # Selection shows history
      select_proc = proc { |*| on_watch_select }
      @app.command(:bind, watch_tree, '<<TreeviewSelect>>', select_proc)

      # Right-click to unwatch
      @app.command(:menu, "#{NB}.watches.ctx", tearoff: 0)
      unwatch_proc = proc { |*| unwatch_selected }
      @app.command("#{NB}.watches.ctx", 'add', 'command',
        label: 'Unwatch', command: unwatch_proc)

      @app.command(:bind, watch_tree, '<Button-3>', proc { |*|
        @app.tcl_eval("
          set item [#{watch_tree} identify item [winfo pointerx #{watch_tree}] [winfo pointery #{watch_tree}]]
          if {$item ne {}} { #{watch_tree} selection set $item }
        ")
        @app.tcl_eval("tk_popup #{NB}.watches.ctx [winfo pointerx .] [winfo pointery .]")
      })
    end

    def add_watch(name)
      return if @watches.key?(name)

      # Register Tcl trace on the variable
      cb_id = @app.register_callback(proc { |var_name, index, *|
        record_watch(var_name, index)
      })

      @app.tcl_eval("trace add variable #{Teek.make_list(name)} write {ruby_callback #{cb_id}}")

      @watches[name] = { cb_id: cb_id, values: [] }

      # Capture current value
      record_watch(name, nil)

      update_watches_ui
    end

    def remove_watch(name)
      info = @watches.delete(name)
      return unless info

      # Remove Tcl trace
      @app.tcl_eval(
        "trace remove variable #{Teek.make_list(name)} write {ruby_callback #{info[:cb_id]}}"
      )
      @app.unregister_callback(info[:cb_id])

      update_watches_ui
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: remove_watch(#{name}): #{e.message}"
    end

    def record_watch(name, index)
      watch = @watches[name]
      return unless watch

      val = begin
        if index && !index.empty?
          @app.tcl_eval("set #{Teek.make_list(name)}(#{index})")
        else
          @app.command(:set, name)
        end
      rescue Teek::TclError
        "(undefined)"
      end

      entry = { value: val, time: Time.now }
      watch[:values] << entry
      watch[:values].shift if watch[:values].size > WATCH_HISTORY_SIZE

      # Update this row in-place
      update_watch_row(name, watch)
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: record_watch(#{name}): #{e.message}"
    end

    def update_watch_row(name, info)
      watch_tree = "#{NB}.watches.tree"
      item_id = "watch_#{name}"

      current = info[:values].last
      display_val = current ? current[:value] : ""
      display_val = display_val[0, 200] + "..." if display_val.size > 200

      if @app.command(watch_tree, 'exists', item_id) == "1"
        @app.command(watch_tree, 'item', item_id,
          values: Teek.make_list(display_val, info[:values].size.to_s))
      else
        @app.command(watch_tree, 'insert', '', 'end',
          id: item_id, text: name,
          values: Teek.make_list(display_val, info[:values].size.to_s))
      end
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: update_watch_row(#{name}): #{e.message}"
    end

    def refresh_watches
      @watches.each do |name, info|
        # Re-read current value
        val = begin
          @app.command(:set, name)
        rescue Teek::TclError
          "(undefined)"
        end

        current = info[:values].last
        if current.nil? || current[:value] != val
          info[:values] << { value: val, time: Time.now }
          info[:values].shift if info[:values].size > WATCH_HISTORY_SIZE
        end

        update_watch_row(name, info)
      end
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: refresh_watches: #{e.message}"
    end

    def update_watches_ui
      watch_tree = "#{NB}.watches.tree"
      help = "#{NB}.watches.help"
      history = "#{NB}.watches.history"

      # Update tab label with count
      label = @watches.empty? ? "Watches" : "Watches (#{@watches.size})"
      @app.command(NB, 'tab', "#{NB}.watches", text: label)

      if @watches.empty?
        @app.command(:pack, 'forget', watch_tree) rescue nil
        @app.command(:pack, 'forget', "#{NB}.watches.vsb") rescue nil
        @app.command(:pack, 'forget', history) rescue nil
        @app.command(:pack, help, expand: 1)
      else
        @app.command(:pack, 'forget', help) rescue nil
        @app.command(:pack, "#{NB}.watches.vsb", side: :right, fill: :y)
        @app.command(:pack, watch_tree, fill: :both, expand: 1)
        @app.command(:pack, history, side: :bottom, fill: :x, before: watch_tree)
      end

      refresh_watches
    end

    def on_watch_select
      watch_tree = "#{NB}.watches.tree"
      history_w = "#{NB}.watches.history"

      sel = @app.command(watch_tree, 'selection')
      return if sel.empty?

      name = @app.command(watch_tree, 'item', sel, '-text')
      info = @watches[name]
      return unless info

      lines = info[:values].reverse.map { |e|
        ts = e[:time].strftime("%H:%M:%S.%L")
        val = e[:value]
        val = val[0, 100] + "..." if val.size > 100
        "  [#{ts}] #{val}"
      }.join("\n")
      text = "#{name} (#{info[:values].size} changes)\n#{lines}"

      @app.command(history_w, 'configure', state: :normal)
      @app.command(history_w, 'delete', '1.0', 'end')
      @app.command(history_w, 'insert', '1.0', text)
      @app.command(history_w, 'configure', state: :disabled)
    end

    def unwatch_selected
      watch_tree = "#{NB}.watches.tree"
      sel = @app.command(watch_tree, 'selection')
      return if sel.empty?

      name = @app.command(watch_tree, 'item', sel, '-text')
      remove_watch(name)
    end

    # ── Auto-refresh ─────────────────────────────────────────

    def start_auto_refresh
      @auto_refresh_id = @app.after(1000) do
        auto_refresh_tick
        start_auto_refresh
      end
    end

    def auto_refresh_tick
      vars_tree = "#{NB}.vars.tree"

      new_data = fetch_variables
      unless new_data == @var_data
        # Preserve selection and scroll
        sel = @app.command(vars_tree, 'selection') rescue ""
        scroll = Teek.split_list(@app.command(vars_tree, 'yview')) rescue nil

        @var_data = new_data
        update_variables_incremental

        # Restore selection if item still exists
        unless sel.empty?
          if @app.command(vars_tree, 'exists', sel) == "1"
            @app.command(vars_tree, 'selection', 'set', sel)
          end
        end

        # Restore scroll position
        if scroll && scroll.size == 2
          @app.command(vars_tree, 'yview', 'moveto', scroll[0])
        end
      end

      refresh_watches
    rescue Teek::TclError => e
      $stderr.puts "teek debugger: auto-refresh error: #{e.message}"
    end

    # ── Widget tree helpers ──────────────────────────────────

    def sync_widget_tree
      @app.widgets.sort_by { |path, _| path.count('.') }.each do |path, info|
        on_widget_created(path, info[:class])
      end
    end

    def parent_tree_id(path)
      last_dot = path.rindex('.')
      return '.' if last_dot.nil? || last_dot == 0
      path[0...last_dot]
    end

    def tk_basename(path)
      last_dot = path.rindex('.')
      return path if last_dot.nil?
      path[(last_dot + 1)..]
    end

    def ensure_parent_exists(path)
      tree = "#{NB}.widgets.tree"
      parent = parent_tree_id(path)
      return if parent == '.'
      return if @app.command(tree, 'exists', parent) == "1"

      ensure_parent_exists(parent)
      name = tk_basename(parent)
      cls = begin
        @app.command(:winfo, 'class', parent)
      rescue Teek::TclError
        "?"
      end
      @app.command(tree, 'insert', parent_tree_id(parent), 'end',
        id: parent, text: name, values: Teek.make_list(parent, cls), open: 1)
    end
  end
end
