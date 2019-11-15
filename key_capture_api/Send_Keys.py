'''
Test which will capture select keyboard key presses, and will
signal them to x4 accordingly, to be bound x4-side to MD cues.

Uses the pynput package (not included with anaconda or standard python).

'''
'''
TODO:
    Repack much of this functionality into a class or two, instead
    of messy global vars and such.
'''
'''
Keyboard capture example here:
https://pynput.readthedocs.io/en/latest/keyboard.html

This Listener appears to inherit from Thread, to be started and run
in parallel.
When keys are pressed, it feeds a key object to a provided callback function.

"The key parameter passed to callbacks is a pynput.keyboard.Key, for special
keys, a pynput.keyboard.KeyCode for normal alphanumeric keys, or just None
for unknown keys."

That page also advises doing very little in the listener callback functions,
since long running callbacks can cause problems with new input capture.
'''
'''
Note:
    The various keys map to keycodes, found in pynput source in _win32.py
    for windows, _dawrin.py for unix.
    In here, shift_l and shift map to the same keycode, which causes a
    hiccup if trying to match x4 key requests to pynput pressed keys
    based on name, since x4 may request shift_l and pynput will only
    return shift.

    An intermediate step of mapping x4 key names to keycodes can be used
    to improve robustness.  The shift_l keycode would then match a
    keypress of shift. This will only be done for special keys; pynput
    doesn't appear to support integer codes for alphanumeric keys.
'''

import sys
import time
import threading
import win32file
import copy
from collections import defaultdict

## This will be specific to windows for now.
if not sys.platform == 'win32':
    raise Exception("Only windows supported at this time.")

from pynput import keyboard
from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
# Can use this to know if x4 has focus.
from win32gui import GetWindowText, GetForegroundWindow

# Name of the pipe to use.
pipe_name = 'x4_keys'

# Flag to do a test run with the pipe client handled in python instead
# of x4.
# Note: if doing this from a console window, pynput prevents ctrl-c
# exits, but ctrl-pause/break will work.
test_python_client = 0

# Expected window title, for when this captures keys.
# Normally x4, but changes for python testing.
# For python, there may be a path prefix, so this will just check the
# final part of the window title.
window_title = 'X4'
if test_python_client:
    # TODO: make more robust, eg. work with cmd.
    window_title = 'python.exe'


def main():
    '''
    Entry function for this server.

    This will transmit key presses to x4, and x4 will return acks as it
    processes them. Total keys in flight will be limited.

    Uses pynput for key capture. For a little extra security, pynput
    will ignore keys while x4 lacks focus.

    Note: by experience, x4 side sometimes has several seconds of lag
    before processing keys sent.
    '''
    # Testing keyboard class types/attributes.
    #a = keyboard.KeyCode(char='a')
    #shift_l = keyboard.Key.shift_l.value


    # Set up the pipe and connect to x4.
    pipe = Pipe_Server(pipe_name)
        
    # For python testing, kick off a client thread.
    if test_python_client:
        # Set up the reader in another thread.
        reader_thread = threading.Thread(target = Pipe_Client_Test)
        reader_thread.start()

    # Wait for client.
    pipe.Connect()

    # Announce this as global, since it gets reassigned at one point.
    global key_buffer
    # Clear any old data before continuing, since it may have stuff from
    # the last time x4 was connected.
    key_buffer.clear()
    
    # Max keys in flight to x4, not yet acknowledged.
    max_keys_piped = 10
    # Current count of piped keys.
    keys_piped = 0
    
    # List of keys being recorded.
    # TODO: delete when combo support finished.
    keys_to_record = set()
    
    # See comments on this elsewhere.
    # Setting a default to make sure this is known.
    categorized_combo_specs = defaultdict(list)

    # Set of keys (Key or KeyCode) in a pressed state.
    # Updated when key_buffer is processed.
    # Note: only tracks keys of interest to the combos. Assumes combos
    # will not be changing often enough to worry about tracking unused
    # keys that might be used in the future.
    keys_down = set()

    
    # Note: x4 will sometimes send non-ack messages to the pipe, and there
    # is no way to know when they will arrive other than testing it.
    # This cannot be done in one thread with blocking Reads/Writes.
    # While conceptually spinning off a second Read thread will work,
    # it was tried and failed, as the write thread got stuck on Write
    # while the read thread was waiting on Read.
    # The solution is to set the pipe to non-blocking, and do everything
    # in a single thread.
    pipe.Set_Nonblocking()
   
            
    if 0:
        key_buffer.append((1,1,'$a'))
        key_buffer.append((1,1,'$s'))
        key_buffer.append((1,1,'$d'))
        key_buffer.append((1,1,'$f'))

    try:
        while 1:
        
            # Determine if x4 is the focused window.
            # Get the window title of whatever window has focus.
            focused_window_title = GetWindowText(GetForegroundWindow())

            # Ignore if not the wanted window.
            # Only check the end of the title, to avoid paths in the cmd window
            # when testing in python.
            if focused_window_title.endswith(window_title):
                x4_has_focus = True
                # Start the keyboard listener if not yet running.
                Start_Keyboard_Listener()

            else:
                x4_has_focus = False
                # When x4 loses focus, assume all pressed keys are released
                # upon returning to x4. This addresses the common case of
                # alt-tabbing out (which leaves alt as pressed when clicking
                # back into x4 otherwise).
                # An alternate solution would be to capture all keys even
                # when x4 lacks focus, but while that was tried and worked,
                # it was distasteful.
                keys_down.clear()
                # Stop the keyboard listener when tabbed out if it is running.
                Stop_Keyboard_Listener()
            

            # Try to read any data.
            message = pipe.Read()
            if message != None:
                print('Received: ' + message)

                # Ignore pings; they were just testing the pipe.
                if message == 'ping':
                    pass

                # Acks will update the piped keys counter.
                # TODO: think about how to make more robust; really want a
                # way to sample the client pipe fill.
                # Note: if something messed up x4 side somehow, its md cue may
                # cancel a read request (sends no ack) but the lua side would
                # still process the read (gets the combo), in which case a combo
                # is transferred but not acked.
                # So, instead of tracking acks, try to think of another approach.
                # TODO; keys_piped check commented out further below.
                elif message == 'ack':
                    keys_piped -= 1

                # Update the key list.
                elif message.startswith('setkeys:'):
                    # Each new message has a full key set, so ignore prior keys.
                    #keys_to_record.clear()

                    # Starts with "setkeys:"; toss that.
                    message = message.replace('setkeys:', '')

                    # Get the new compiled combos.
                    categorized_combo_specs = Update_Combos(message)
                    print('Updated combos to: {}'.format(message))

                    # TODO: if all keys are unregistered, kill off this thread
                    # so it returns to waiting for pipe connection, and the
                    # key capture subthread is no longer running.
                    # Would just need to check for empty combo specs, and
                    # throw a pipe error exception (as expected by
                    # Server_Thread to reboot this module).
                

            # If anything is in the key_buffer, process into key combos.
            if key_buffer:

                # Grab everything out of the key_buffer in one step, to play
                # more nicely with threading (assume interruption at any time).
                # Just do this with rebinding.
                raw_keys = key_buffer
                key_buffer = []

                print('Processing: {}'.format(raw_keys))

                # Process the keys, updating what is pressed and getting any
                # matched combos.
                matched_combos = Process_Key_Events(
                    key_buffer = raw_keys, 
                    keys_down = keys_down, 
                    categorized_combo_specs = categorized_combo_specs)
            
                # Start transmitting.
                for combo in matched_combos:
                    #-Removed; janky and needs better solution.
                    ## Only go up to the max that can be piped at once.
                    #if keys_piped >= max_keys_piped:
                    #    print('Suppressing combo; max pipe reached.')
                    #    break

                    # Transmit to x4.
                    # Note: this doesn't put the '$' back for now, since that
                    # is easier to add in x4 than remove afterwards.
                    print('Sending: ' + combo)
                    pipe.Write(combo)
                    keys_piped += 1


            # General pause between checks.
            # Assuming x4 is at 60 fps, that is 16 ms between frames.
            # Responsiveness here probably doesn't need to be much better than
            # a couple frames, though. 
            # Although, x4 processing will add a frame or two at least.
            # TODO: maybe revisit this timer stepping.
            # TODO: maybe reduce this if any traffic was handled above.
            if x4_has_focus:
                time.sleep(0.040)
            else:
                # Slow down when outside x4, though still quick enough
                # to response when tabbing back in quickly.
                time.sleep(0.200)

    finally:
        # Stop the listener when an error occurs, eg. x4 closing.
        Stop_Keyboard_Listener()
    return


# Set up the keyboard listener.

# Buffer of raw keys pressed. Index 0 is oldest press.
# Each entry is a tuple of:
# (1 for pressed or 0 released, Key or KeyCode).
# TODO: maybe some sort of queue with max size that tosses oldest.
# TODO: rethink buffer limit; it is mostly for safety, but if ever
# hit it will cause problems with detecting key releases (eg. set
# of held keys may have false state).
key_buffer = []
max_keys_buffered = 50

# Scancode dict.
# This will map from windows vk codes to keyboard scancodes.
vk_scancode_mapping = {}

# The listener thread itself.
listener_thread = None

class Key:
    '''
    Locally defined Key object.
    This aims to simplify between pynput Key and KeyCode differences,
    and will also record key scancodes.
    Initializes from a pynput key object.

    Attributes:
    * name
      - String, name of the key.
    * vk
      - Int, the OS virtual keycode.
      - May be ambiguous between different physical keys.
    * code
      - Int, keyboard scancode of the key that was pressed, as decided
        by windows.
      - Some numpad keys will use their normal key alias scancode instead.
        - numpad enter
        - numpad /
    * pressed
      - Bool, if True the key was pressed, else the key was released.
    '''
    def __init__(self, key_object, pressed = None):
        self.pressed = pressed

        # The key vk is either in 'vk' or 'value.vk'.
        if hasattr(key_object, 'vk'):
            self.vk = key_object.vk
            self.name = key_object.char
        else:
            self.vk = key_object.value.vk
            self.name = key_object.name

        # Get the scancode and attach it.
        self.code = vk_scancode_mapping[self.vk]

        # If no name recorded, eg. for special keys (mute, etc.), then
        # just use the keycode raw.
        if not self.name:
            self.name = str(self.code)
        return
    
    def __repr__(self):
        return self.name
    def __str__(self):
        return repr(self)


# Capture key presses into a queue.
def Buffer_Presses(key_object):
    '''
    Function to be called by the key listener on button presses.
    Kept super simple, due to pynput warning about long callbacks.
    '''
    if len(key_buffer) < max_keys_buffered:
        key_buffer.append( Key(key_object, True))
    return
    
def Buffer_Releases(key_object):
    '''
    Function to be called by the key listener on button releases.
    Kept super simple, due to pynput warning about long callbacks.
    '''
    if len(key_buffer) < max_keys_buffered:
        key_buffer.append( Key(key_object, False))
    return

def Keypress_Precheck(msg, data):
    '''
    Function to be called whenever pynput detects an input event.
    Should return True to continue processing the event, else False.
    From a glance at pynput source, this might be called significantly
    ahead of the on_press and on_release callbacks.

    This is mainly used to try to get more key information, since normal
    pynput KeyPress objects use windows keycodes which don't distinguish
    all keys (eg. enter vs numpad_enter).

    Event scanCodes will be added to vk_scancode_mapping, overwriting
    any existing entry.
    '''
    # 'data' is a dict with keys matching those in KBLLHOOKSTRUCT:
    # https://docs.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct
    # Pynput normally returns the vkCode, but scanCode will better match
    # up with x4.
    # Note: goal was to have scancode differ between 'enter' and 'numpad_enter',
    # but in practice even at this low level windows will conflate the two,
    # and just returns the scancode for the normal 'enter' key always.
    vk_scancode_mapping[data.vkCode] = data.scanCode
    return True


def Start_Keyboard_Listener():
    '''
    Start up the keyboard listener thread if it isn't running already.
    Warning: multiple server restarts making fresh listeners led to
    pynput getting in some buggy state where it only returned codes
    instead of letters (eg. b'\x01' instead of 'a').
    '''
    global listener_thread

    # Return early if a thread is already set up.
    if listener_thread:
        return

    print('Starting keyboard listener')
    # Start the listener thread.
    listener_thread = keyboard.Listener(
        on_press   = Buffer_Presses,
        on_release = Buffer_Releases,
        win32_event_filter = Keypress_Precheck)

    listener_thread.start()
    return


def Stop_Keyboard_Listener():
    '''
    Stop any currently running keyboard listener.
    '''
    global listener_thread
    if listener_thread:
        print('Stopping keyboard listener')
        listener_thread.stop()
        # Can't reuse these, so just release and start a fresh
        # one when needed.
        listener_thread = None
    return


def Update_Combos(message):
    '''
    From a suitable "setkeys:" message, compile into the pynput
    key objects it represents, and update the watched-for combos.

    Returns categorized_combo_specs, a dict of lists of tuples of 
    (combo name from a message, compiled list of corresponding pynput keys),
    and keyed by a 6-bit category code matching to which ctrl-alt-shift
    modifier keys must be pressed for the combo.
    A given combo name may be present multiple times, for variations on its 
    compiled combo list.
    '''
    combo_specs = []

    # If all key/combos have been cleared, the rest of the message is blank.
    if not message:
        # Return early.
        return combo_specs

    # Expect each key combo to be prefixed with '$' and end with
    #  ';'.  Can separate on ';$', ignoring first and last char.
    # Note: any '$' or ';' in the combo itself is fine, since they
    #  will always be required to be space separated, and so won't
    #  get matched here.
    combos_requested = message[1:-1].split(';$')

    # Compile these into pynput keys.
    for combo_string in combos_requested:
        # Collect the combo groups; each combo_string may make multiple.
        # Skip any with errors.
        try:
            for combo in Compile_Combo(combo_string):
                combo_specs.append((combo_string, combo))
        except Exception as ex:
            print('Error when handling combo {}, exception: {}'.format(combo_string, ex))
            continue


    # Categorize combos based on the modifier keys used.
    # For variants of modifier keys, encode into an integer category label.
    categorized_combo_specs = defaultdict(list)
    for combo_spec in combo_specs:

        # Category code; starts at 0, gets bits set.
        category = 0
        # Check each modifier.
        for index, mod_key in enumerate(mod_keycodes):
            if mod_key in combo_spec[1]:
                # Set a bit for this position.
                category += (1 << index)

        # Add this combo to the dict.
        categorized_combo_specs[category].append(combo_spec)

    return categorized_combo_specs



def Compile_Combo(combo_string):
    '''
    Translates a key/combo string from x4 into separate key strings, 
    with generic shift-alt-ctrl keys being uniquified. Normal alphanumeric
    entries are kept as strings, but special keys will be remapped to
    their integer key codes.

    Returns a list of lists of strings and integers.
    '''
    '''
    Note on generic keyname combos:

        For a combo to be matched on a key press, all earlier keys in
        the combo must be in a pressed state when the final key of the
        combo is pressed.

        Input combos are represented using a mix of alphanumeric characters and
        names of Keys from https://pynput.readthedocs.io/en/latest/keyboard.html
        Eg. 'space', 'shift_l', etc.

        Each key in an input combo will be separated by a space (' ') character;
        spacebar itself would be 'space'.
        Eg. "shift_l a" or "space +".    

        Each single-letter key name is treated as alphanumeric, while multi-letter
        key names are mapped to special keys (shift, space, etc.).

        For now, these key names will not distinguish between numpad
        inputs and normal keys.

    Note on egosoft keycodes:

        These come from using the ego menu system, and have the form:
            "code <input type> <key code> <sign>"
        For keyboard inputs, type is always 1, sign is always 0.
        So for now, the expected form is:
            "code 1 <key code> 0"

        Keycodes use standard keyboard encoding, which differs from the OS
        codes and those used by pynput.
        Further, modifiers for shift and ctrl are baked into the keycode's
        high byte:
            shift: 0x100
            ctrl : 0x400

        Numpad keys will use different keycodes than standard keys.

    '''
    # Process egosoft keycodes.
    # Aim is to unify their format with generic key combo strings, so
    # both can share the subsequent code.
    if combo_string.startswith('code '):
        combo = Ego_Keycode_To_Combo(combo_string)
    else:
        # Break out the requested keys by spacing.
        combo = combo_string.split()
    
    # For generic shift-alt-ctrl, uniquify them into left/right
    # versions. This could potentially generate up to 6 sub-combos
    # if all such keys are used.
    # Process combo_names into a new list of lists.
    # Seed this with a single empty list.
    combo_list = [[]]
    for name in combo:
        if name in ['shift','alt','ctrl']:

            # Triplicate all groups.
            bare_combos = combo_list
            l_combos = copy.deepcopy(combo_list)
            r_combos = copy.deepcopy(combo_list)

            # Add uniquified names.
            # Left, right, and unsuffixed versions are kept.
            for groups, suffix in zip([bare_combos, l_combos, r_combos], ['','_l','_r']):
                for group in groups:
                    group.append(name + suffix)
            # Stick the new groups together again.
            combo_list = bare_combos + l_combos + r_combos

        else:
            # Add the name to all groups.
            for group in combo_list:
                group.append(name)
                

    # Map the named keys to pynput keycodes.
    # In practice, this will mean alphanumeric keys remain strings, but
    # special keys map to integers.
    # TODO: alphanumeric also as keycodes.
    encoded_combo_list = []
    for combo in combo_list:
    
        # Wrap this in case of getting bad combos, like a "null" for an
        # unfilled mission director var.
        try:
            # Set up a list for these keys, and add to the list of combos.
            encoded_combo = []
    
            # Map to Key and KeyCode objects.
            for key_name in combo:
    
                # If empty, something weird happened like double spacing in the
                #  user input. Treat that as okay, but ignore this split element.
                if not key_name:
                    continue

                # Translate to a scancode.
                code = _name_to_scancode_dict.get(key_name, None)
                assert code

                # -Removed; standardized key scancode handling earlier.
                ## If the name is a special name to map to a virtual key
                ## manually, look it up here.
                ## This is mainly for numpad inputs, which pynput doesn't
                ## distinguish from normal key names.
                #if key_name in _keyname_to_vk_dict:
                #    key = _keyname_to_vk_dict[key_name]    
                #
                ## Single letters are alphanumeric.
                ## There is no way to translate this into a virtual key,
                ##  since packing it into a KeyCode will just create that
                ##  object with a defined 'char' but no 'vk'.
                ## So, keep these letters as-is.
                #elif len(key_name) == 1:
                #    key = key_name
                #
                ## Longer names will map to existing defined pynput
                ## keys (shift, enter, etc.).
                #else:
                #    # Look up the enumerator entry, get its value, a KeyCode.
                #    # From the KeyCode, use the vk attribute for the integer
                #    # key value.
                #    key = getattr(keyboard.Key, key_name).value.vk
    
                encoded_combo.append(code)
            
            # It is possible this encoded_combo is already present, due
            #  to modifier keycode aliasing.
            # Only record the new combo if unique.
            if not any(encoded_combo == x for x in encoded_combo_list):
                encoded_combo_list.append(encoded_combo)

        except Exception as ex:
            print("Error processing combo '{}', exception: {}".format(combo, ex))
            
    return encoded_combo_list


def Process_Key_Events(key_buffer, keys_down, categorized_combo_specs):
    '''
    Processes raw key presses/releases captured into key_buffer,
    updating keys_down and matching to combos in combo_specs.
    Returns a list of combos matched, using string names from
    the categorized_combo_specs entries.
    '''
    matched_combo_names = []

    # Translate combo_dict into a set of keys of interest.
    # TODO: do this once when combo_specs built and reuse.
    keys_in_combos = set()
    for combo_specs in categorized_combo_specs.values():
        for _, combo in combo_specs:
            keys_in_combos.update(combo)
    # Include modifier always, left/right variations.
    keys_in_combos.update(mod_keycodes)


    # Loop over the key events in recorded order.
    for key_event in key_buffer:

        # Use the scancode for the key tracking.
        key = key_event.code
        
        # If key is not of interest, ignore it.
        if key not in keys_in_combos:
            continue

        # Update pressed/released state.
        # Note: a raw modifier key (eg. shift_l) will be categorized as
        # needing itself held down, so update keys_down prior to
        # checking the combos.
        if key_event.pressed:
            keys_down.add(key)
        elif key in keys_down:
            keys_down.remove(key)


        # On press, match up against combos.
        if key_event.pressed:

            # Get which modifier keys are currently held, and their
            #  corresponding category code.
            category = 0
            # Check each modifier.
            for index, mod_key in enumerate(mod_keycodes):
                if mod_key in keys_down:
                    # Add a 1-hot bit.
                    category += (1 << index)

            print('Keys down: {}'.format(keys_down))

            # Use the appropriate combo category, to filter out those
            # that don't match the modifiers held.
            combo_specs = categorized_combo_specs[category]
            for name, combo in combo_specs:
                # Ignore if this isn't the last key of the combo.
                if key != combo[-1]:
                    continue

                # All combo keys before the last need to be down.
                # Note: this ends up duplicating checks of modifier keys
                #  for now, but is handy to catch a mod key as a standalone.
                if all(x in keys_down for x in combo[1:]):
                    # This is a combo match.
                    matched_combo_names.append(name)                        

    return matched_combo_names


def Ego_Keycode_To_Combo(combo_string):
    '''
    Takes a combo_string from egosoft's input capture, and translates
    to a key combo. Returns a list with 1-3 items: 'shift' and 'ctrl'
    as optional modifiers, and the string name of the main key.

    The combo_string should begin with "code ".
    '''
    assert combo_string.startswith('code ')
    
    # Obtain the generic keyboard keycode.
    # Convert this from string to int.
    keycode = int(combo_string.split()[2])

    # Convert into a new generic combo list.
    combo = []

    # Isolate modifiers.
    # Note: ego code doesn't distinguish between left/right keys.
    # Ctrl at 0x400.
    if keycode & 0x400:
        keycode -= 0x400
        combo.append('ctrl')

    # Shift at 0x100.
    if keycode & 0x100:
        keycode -= 0x100
        combo.append('shift')

    # Convert the remainder to a key name.
    # Note: shortly after this the name will convert back into a code,
    #  which will be the same for most keys, but some aliased keys will
    #  get swapped to the windows returned scancode.
    keyname = _scancode_to_name_dict.get(keycode, None)
    # Error if the keyname not supported.
    if not keyname:
        raise Exception("Ego keycode {} not supported".format(keycode))
    combo.append(keyname)

    return combo


def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Pick some keys to capture.
    # Some given as MD registered string combos, some as ego keycodes.
    # 286 is shift-a, 82 is numpad 0.
    keys = 'setkeys:$a;$shift_l a;$shift_l s;$ctrl_l d;$alt_r f;$code 1 286 0;$code 1 82 0;'
    pipe.Write(keys)

    # Capture a few characters.
    for _ in range(50):
        char = pipe.Read()
        print(char)
        pipe.Write('ack')
            
    return



# Dict mapping egosoft keycodes to key name strings understood by pynput.
# Ego keys appear to match this (excepting special shift/ctrl handling):
#  https://github.com/wgois/OIS/blob/master/includes/OISKeyboard.h
# TODO: think about numpad keys.
# TODO: maybe put in another python module.
# TODO: maybe decimal instead of hex, to make easier to debug.
_scancode_to_name_dict = {    
    0x00 : "",            # KC_UNASSIGNED
    0x01 : "",            # KC_ESCAPE
    0x02 : "1",           # KC_1
    0x03 : "2",           # KC_2
    0x04 : "3",           # KC_3
    0x05 : "4",           # KC_4
    0x06 : "5",           # KC_5
    0x07 : "6",           # KC_6
    0x08 : "7",           # KC_7
    0x09 : "8",           # KC_8
    0x0A : "9",           # KC_9
    0x0B : "0",           # KC_0
    0x0C : "-",           # KC_MINUS // - on main keyboard
    0x0D : "=",           # KC_EQUALS
    0x0E : "backspace",   # KC_BACK // backspace
    0x0F : "tab",         # KC_TAB
    0x10 : "q",           # KC_Q
    0x11 : "w",           # KC_W
    0x12 : "e",           # KC_E
    0x13 : "r",           # KC_R
    0x14 : "t",           # KC_T
    0x15 : "y",           # KC_Y
    0x16 : "u",           # KC_U
    0x17 : "i",           # KC_I
    0x18 : "o",           # KC_O
    0x19 : "p",           # KC_P
    0x1A : "[",           # KC_LBRACKET
    0x1B : "]",           # KC_RBRACKET
    0x1C : "enter",       # KC_RETURN // Enter on main keyboard
    0x1D : "ctrl_l",      # KC_LCONTROL
    0x1E : "a",           # KC_A
    0x1F : "s",           # KC_S
    0x20 : "d",           # KC_D
    0x21 : "f",           # KC_F
    0x22 : "g",           # KC_G
    0x23 : "h",           # KC_H
    0x24 : "j",           # KC_J
    0x25 : "k",           # KC_K
    0x26 : "l",           # KC_L
    0x27 : ";",           # KC_SEMICOLON
    0x28 : "'",           # KC_APOSTROPHE
    0x29 : "`",           # KC_GRAVE // accent
    0x2A : "shift_l",     # KC_LSHIFT
    0x2B : "\\",          # KC_BACKSLASH
    0x2C : "z",           # KC_Z
    0x2D : "x",           # KC_X
    0x2E : "c",           # KC_C
    0x2F : "v",           # KC_V
    0x30 : "b",           # KC_B
    0x31 : "n",           # KC_N
    0x32 : "m",           # KC_M
    0x33 : ",",           # KC_COMMA
    0x34 : ".",           # KC_PERIOD // . on main keyboard
    0x35 : "/",           # KC_SLASH // / on main keyboard
    0x36 : "shift_r",     # KC_RSHIFT
    0x37 : "num_*",           # KC_MULTIPLY // * on numeric keypad
    0x38 : "alt_l",       # KC_LMENU // left Alt
    0x39 : "space",       # KC_SPACE
    0x3A : "caps_lock",   # KC_CAPITAL
    0x3B : "f1",          # KC_F1
    0x3C : "f2",          # KC_F2
    0x3D : "f3",          # KC_F3
    0x3E : "f4",          # KC_F4
    0x3F : "f5",          # KC_F5
    0x40 : "f6",          # KC_F6
    0x41 : "f7",          # KC_F7
    0x42 : "f8",          # KC_F8
    0x43 : "f9",          # KC_F9
    0x44 : "f10",         # KC_F10
    0x45 : "num_lock",    # KC_NUMLOCK
    0x46 : "scroll_lock", # KC_SCROLL // Scroll Lock

    0x47 : "num_7",            # KC_NUMPAD7
    0x48 : "num_8",            # KC_NUMPAD8
    0x49 : "num_9",            # KC_NUMPAD9
    0x4A : "num_-",            # KC_SUBTRACT // - on numeric keypad
    0x4B : "num_4",            # KC_NUMPAD4
    0x4C : "num_5",            # KC_NUMPAD5
    0x4D : "num_6",            # KC_NUMPAD6
    0x4E : "num_+",            # KC_ADD // + on numeric keypad
    0x4F : "num_1",            # KC_NUMPAD1
    0x50 : "num_2",            # KC_NUMPAD2
    0x51 : "num_3",            # KC_NUMPAD3
    0x52 : "num_0",            # KC_NUMPAD0
    0x53 : "num_.",            # KC_DECIMAL // . on numeric keypad
    0x56 : "",            # KC_OEM_102 // < > | on UK/Germany keyboards
    0x57 : "f11",            # KC_F11
    0x58 : "f12",            # KC_F12
    0x64 : "f13",            # KC_F13 // (NEC PC98)
    0x65 : "f14",            # KC_F14 // (NEC PC98)
    0x66 : "f15",            # KC_F15 // (NEC PC98)
    0x70 : "",            # KC_KANA // (Japanese keyboard)
    0x73 : "",            # KC_ABNT_C1 // / ? on Portugese (Brazilian) keyboards
    0x79 : "",            # KC_CONVERT // (Japanese keyboard)
    0x7B : "",            # KC_NOCONVERT // (Japanese keyboard)
    0x7D : "",            # KC_YEN // (Japanese keyboard)
    0x7E : "",            # KC_ABNT_C2 // Numpad . on Portugese (Brazilian) keyboards
    # How is this different than normal =?
    0x8D : "",            # KC_NUMPADEQUALS // = on numeric keypad (NEC PC98)
    0x90 : "",            # KC_PREVTRACK // Previous Track (KC_CIRCUMFLEX on Japanese keyboard)
    0x91 : "",            # KC_AT // (NEC PC98)
    0x92 : "",            # KC_COLON // (NEC PC98)
    0x93 : "",            # KC_UNDERLINE // (NEC PC98)
    0x94 : "",            # KC_KANJI // (Japanese keyboard)
    0x95 : "",            # KC_STOP // (NEC PC98)
    0x96 : "",            # KC_AX // (Japan AX)
    0x97 : "",            # KC_UNLABELED // (J3100)
    0x99 : "",            # KC_NEXTTRACK // Next Track
    # Aliases to normal enter.
    0x9C : "enter",       # KC_NUMPADENTER // Enter on numeric keypad
    0x9D : "ctrl_r",      # KC_RCONTROL
    0xA0 : "",            # KC_MUTE // Mute
    0xA1 : "",            # KC_CALCULATOR // Calculator
    0xA2 : "",            # KC_PLAYPAUSE // Play / Pause
    0xA4 : "",            # KC_MEDIASTOP // Media Stop
    0xAA : "",            # KC_TWOSUPERIOR // ² on French AZERTY keyboard (same place as ~ ` on QWERTY)
    0xAE : "",            # KC_VOLUMEDOWN // Volume -
    0xB0 : "",            # KC_VOLUMEUP // Volume +
    0xB2 : "",            # KC_WEBHOME // Web home
    0xB3 : "",            # KC_NUMPADCOMMA // , on numeric keypad (NEC PC98)
    # Aliases to normal /.
    0xB5 : "/",           # KC_DIVIDE // / on numeric keypad
    0xB7 : "",            # KC_SYSRQ
    0xB8 : "alt_r",       # KC_RMENU // right Alt
    0xC5 : "pause",       # KC_PAUSE // Pause
    0xC7 : "home",        # KC_HOME // Home on arrow keypad
    0xC8 : "up",          # KC_UP // UpArrow on arrow keypad
    0xC9 : "page_up",     # KC_PGUP // PgUp on arrow keypad
    0xCB : "left",        # KC_LEFT // LeftArrow on arrow keypad
    0xCD : "right",       # KC_RIGHT // RightArrow on arrow keypad
    0xCF : "end",         # KC_END // End on arrow keypad
    0xD0 : "down",        # KC_DOWN // DownArrow on arrow keypad
    0xD1 : "page_down",   # KC_PGDOWN // PgDn on arrow keypad
    0xD2 : "insert",      # KC_INSERT // Insert on arrow keypad
    0xD3 : "delete",      # KC_DELETE // Delete on arrow keypad
    0xDB : "win_l",       # KC_LWIN // Left Windows key
    0xDC : "win_r",       # KC_RWIN // Right Windows key
    0xDD : "",            # KC_APPS // AppMenu key
    0xDE : "",            # KC_POWER // System Power
    0xDF : "",            # KC_SLEEP // System Sleep
    0xE3 : "",            # KC_WAKE // System Wake
    0xE5 : "",            # KC_WEBSEARCH // Web Search
    0xE6 : "",            # KC_WEBFAVORITES // Web Favorites
    0xE7 : "",            # KC_WEBREFRESH // Web Refresh
    0xE8 : "",            # KC_WEBSTOP // Web Stop
    0xE9 : "",            # KC_WEBFORWARD // Web Forward
    0xEA : "",            # KC_WEBBACK // Web Back
    0xEB : "",            # KC_MYCOMPUTER // My Computer
    0xEC : "",            # KC_MAIL // Mail
    0xED : "",            # KC_MEDIASELECT // Media Select
    }
# Reversal of the above, to map defined names to scancodes.
# Where a name is reused, the lowerscancode is kept.
# (Iterates in reverse sorted order, so lower scancode wins.)
_name_to_scancode_dict = { v:k for k,v in sorted(_scancode_to_name_dict.items(), reverse = True)}


# List of modifier key names, used a couple places to categorize key combos.
# These are left/right versions, as well as the plain version, since
# 'shift' was observed to be returned plain for left-shift.
mod_keys = ['alt_l','alt_r',
            'ctrl_l','ctrl_r',
            'shift_l','shift_r',]
# The associated integer key codes.
mod_keycodes = [_name_to_scancode_dict[x] for x in mod_keys]


# -Removed; working in scancodes earlier.
# Dict mapping special keynames to virtual keycodes.
# Codes found at:
# https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
# These are also present in pynput._util.win32_vks.py.
#_keyname_to_vk_dict = {
#    'num_0' : 0x60,
#    'num_1' : 0x61,
#    'num_2' : 0x62,
#    'num_3' : 0x63,
#    'num_4' : 0x64,
#    'num_5' : 0x65,
#    'num_6' : 0x66,
#    'num_7' : 0x67,
#    'num_8' : 0x68,
#    'num_9' : 0x69,
#    'win_l' : 0x5B,
#    'win_r' : 0x5C,
#    }
## Convenience reversal of the above dict, mostly for keycodes as dict keys
## for easy definition checks.
#_vk_to_keyname_dict = { v:k for k,v in _keyname_to_vk_dict.items()}