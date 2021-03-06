/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The main account editor window.
 */
public class Accounts.Editor : Gtk.Dialog {


    private const ActionEntry[] ACTION_ENTRIES = {
        { GearyController.ACTION_REDO, on_redo },
        { GearyController.ACTION_UNDO, on_undo },
    };


    internal static void seperator_headers(Gtk.ListBoxRow row,
                                           Gtk.ListBoxRow? first) {
        if (first == null) {
            row.set_header(null);
        } else if (row.get_header() == null) {
            row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
        }
    }


    internal Manager accounts { get; private set; }


    private SimpleActionGroup actions = new SimpleActionGroup();

    private Gtk.Stack editor_panes = new Gtk.Stack();
    private EditorListPane editor_list_pane;

    private Gee.LinkedList<EditorPane> editor_pane_stack =
        new Gee.LinkedList<EditorPane>();


    public Editor(GearyApplication application, Gtk.Window parent) {
        this.application = application;
        this.accounts = application.controller.account_manager;

        set_default_size(700, 450);
        set_icon_name(GearyApplication.APP_ID);
        set_modal(true);
        set_title(_("Accounts"));
        set_transient_for(parent);

        get_content_area().border_width = 0;
        get_content_area().add(this.editor_panes);

        this.editor_panes.set_transition_type(
            Gtk.StackTransitionType.SLIDE_LEFT_RIGHT
        );
        this.editor_panes.notify["visible-child"].connect_after(on_pane_changed);
        this.editor_panes.show();

        this.actions.add_action_entries(ACTION_ENTRIES, this);
        insert_action_group("win", this.actions);

        get_action(GearyController.ACTION_UNDO).set_enabled(false);
        get_action(GearyController.ACTION_REDO).set_enabled(false);

        this.editor_list_pane = new EditorListPane(this);
        push(this.editor_list_pane);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;

        // Allow the user to use Esc, Back and Alt+arrow keys to
        // navigate between panes.
        if (get_current_pane() != this.editor_list_pane) {
            Gdk.ModifierType state = (
                event.state & Gtk.accelerator_get_default_mod_mask()
            );
            bool is_ltr = (get_direction() == Gtk.TextDirection.LTR);
            if (event.keyval == Gdk.Key.Escape ||
                event.keyval == Gdk.Key.Back ||
                (state == Gdk.ModifierType.MOD1_MASK &&
                 (is_ltr && event.keyval == Gdk.Key.Left) ||
                 (!is_ltr && event.keyval == Gdk.Key.Right))) {
                pop();
                ret = Gdk.EVENT_STOP;
            }
        }

        if (ret != Gdk.EVENT_STOP) {
            ret = base.key_press_event(event);
        }

        return ret;
    }

    public override void destroy() {
        this.editor_panes.notify["visible-child"].disconnect(on_pane_changed);
        base.destroy();
    }

    internal void push(EditorPane pane) {
        // Since we keep old, already-popped panes around (see pop for
        // details), when a new pane is pushed on they need to be
        // truncated.
        EditorPane current = get_current_pane();
        int target_length = this.editor_pane_stack.index_of(current) + 1;
        while (target_length < this.editor_pane_stack.size) {
            EditorPane old = this.editor_pane_stack.remove_at(target_length);
            this.editor_panes.remove(old);
        }

        get_action(GearyController.ACTION_UNDO).set_enabled(false);
        get_action(GearyController.ACTION_REDO).set_enabled(false);

        // Now push the new pane on
        this.editor_pane_stack.add(pane);
        this.editor_panes.add(pane);
        this.editor_panes.set_visible_child(pane);
    }

    internal void pop() {
        // One can't simply remove old panes fro the GTK stack since
        // there won't be any transition between them - the old one
        // will simply disappear. So we need to keep old, popped panes
        // around until a new one is pushed on.
        EditorPane current = get_current_pane();
        int prev_index = this.editor_pane_stack.index_of(current) - 1;
        EditorPane prev = this.editor_pane_stack.get(prev_index);
        this.editor_panes.set_visible_child(prev);
    }

    internal GLib.SimpleAction get_action(string name) {
        return (GLib.SimpleAction) this.actions.lookup_action(name);
    }

    internal void remove_account(Geary.AccountInformation account) {
        this.editor_panes.set_visible_child(this.editor_list_pane);
        this.editor_list_pane.remove_account(account);
    }

    private inline EditorPane? get_current_pane() {
        return this.editor_panes.get_visible_child() as EditorPane;
    }

    private void on_undo() {
        CommandPane? pane = get_current_pane() as CommandPane;
        if (pane != null) {
            pane.undo();
        }
    }

    private void on_redo() {
        CommandPane? pane = get_current_pane() as CommandPane;
        if (pane != null) {
            pane.redo();
        }
    }

    private void on_pane_changed() {
        EditorPane? visible = get_current_pane();
        Gtk.Widget? header = null;
        if (visible != null) {
            // Do this in an idle callback since it's not 100%
            // reliable to just call it here for some reason. :(
            GLib.Idle.add(() => {
                    visible.initial_widget.grab_focus();
                    return GLib.Source.REMOVE;
                });
            header = visible.get_header();
        }
        set_titlebar(header);

        CommandPane? commands = visible as CommandPane;
        if (commands != null) {
            commands.update_command_actions();
        }
    }

}


// XXX I'd really like to make EditorPane an abstract class,
// AccountPane an abstract class extending that, and the four concrete
// panes extend those, but the GTK+ Builder XML template system
// requires a template class to designate its immediate parent
// class. I.e. if accounts-editor-list-pane.ui specifies GtkGrid as
// the parent of EditorListPane, then it much exactly be that and not
// an instance of EditorPane, even if that extends GtkGrid. As a
// result, both EditorPane and AccountPane must both be interfaces so
// that the concrete pane classes can derive from GtkGrid directly,
// and everything becomes horrible. See GTK+ Issue #1151:
// https://gitlab.gnome.org/GNOME/gtk/issues/1151

/**
 * Base interface for panes that can be shown by the accounts editor.
 */
internal interface Accounts.EditorPane : Gtk.Grid {


    /** The editor displaying this pane. */
    internal abstract weak Accounts.Editor editor { get; set; }

    /** The editor displaying this pane. */
    internal abstract Gtk.Widget initial_widget { get; }

    /** The GTK header bar to display for this pane. */
    internal abstract Gtk.HeaderBar get_header();

}


/**
 * Interface for editor panes that display a specific account.
 */
internal interface Accounts.AccountPane : EditorPane {


    /** Account being displayed by this pane. */
    internal abstract Geary.AccountInformation account { get; protected set; }


    /**
     * Connects to account signals.
     *
     * Implementing classes should call this in their constructor.
     */
    protected void connect_account_signals() {
        this.account.changed.connect(on_account_changed);
        update_header();
    }

    /**
     * Disconnects from account signals.
     *
     * Implementing classes should call this in their destructor.
     */
    protected void disconnect_account_signals() {
        this.account.changed.disconnect(on_account_changed);
    }

    /**
     * Called when an account has changed.
     *
     * By default, updates the editor's header subtitle.
     */
    private void account_changed() {
        update_header();
    }

    private inline void update_header() {
        get_header().subtitle = this.account.display_name;
    }

    private void on_account_changed() {
        account_changed();
    }

}

/**
 * Interface for editor panes that support undoing/redoing user actions.
 */
internal interface Accounts.CommandPane : EditorPane {


    /** Stack for the user's commands. */
    internal abstract Application.CommandStack commands { get; protected set; }


    /** Un-does the last user action, if enabled. */
    internal virtual void undo() {
        this.commands.undo.begin(null);
    }

    /** Re-does the last user action, if enabled. */
    internal virtual void redo() {
        this.commands.redo.begin(null);
    }

    /**
     * Updates the state of the editor's undo and redo actions.
     */
    internal virtual void update_command_actions() {
        this.editor.get_action(GearyController.ACTION_UNDO).set_enabled(
            this.commands.can_undo
        );
        this.editor.get_action(GearyController.ACTION_REDO).set_enabled(
            this.commands.can_redo
        );
    }

    /**
     * Connects to command stack signals.
     *
     * Implementing classes should call this in their constructor.
     */
    protected void connect_command_signals() {
        this.commands.executed.connect(on_command);
        this.commands.undone.connect(on_command);
        this.commands.redone.connect(on_command);
    }

    /**
     * Disconnects from command stack signals.
     *
     * Implementing classes should call this in their destructor.
     */
    protected void disconnect_command_signals() {
        this.commands.executed.disconnect(on_command);
        this.commands.undone.disconnect(on_command);
        this.commands.redone.disconnect(on_command);
    }

    /**
     * Called when a command is executed, undone or redone.
     *
     * By default, calls {@link update_command_actions}.
     */
    protected virtual void command_executed() {
        update_command_actions();
    }

    private void on_command() {
        command_executed();
    }

}
