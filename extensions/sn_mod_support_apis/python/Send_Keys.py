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

# Verbosity level of console window messages.
verbosity = 1

# Expected window title, for when this captures keys.
# Normally x4, but changes for python testing.
# For python, there may be a path prefix, so this will just check the
# final part of the window title.
window_title = 'X4'
if test_python_client:
    # TODO: make more robust, eg. work with cmd.
    window_title = 'python.exe'


def main(args):
    '''
    Entry function for this server.

    This will transmit key presses to x4, and x4 will return acks as it
    processes them. Total keys in flight will be limited.

    Uses pynput for key capture. For a little extra security, pynput
    will ignore keys while x4 lacks focus.

    Note: by experience, x4 side sometimes has several seconds of lag
    before processing keys sent.
    '''
    # Enable test mode if requested.
    if args['test']:
        global test_python_client
        test_python_client = True

    # Set up the pipe and connect to x4.
    pipe = Pipe_Server(pipe_name)
        
    # For python testing, kick off a client thread.
    if test_python_client:
        # Set up the reader in another thread.
        reader_thread = threading.Thread(target = Pipe_Client_Test)
        reader_thread.start()

    # Wait for client.
    pipe.Connect()

    # Set up the listener class object to use.
    keyboard_listener = Keyboard_Listener()

    # Set up a key combo processor.
    combo_processor = Key_Combo_Processor()

    # Note: x4 will sometimes send non-ack messages to the pipe, and there
    # is no way to know when they will arrive other than testing it.
    # This cannot be done in one thread with blocking Reads/Writes.
    # While conceptually spinning off a second Read thread will work,
    #  it was tried and failed, as the write thread got stuck on Write
    #  while the read thread was waiting on Read since both were waiting
    #  on the same pipe that can only wait on one request.
    # The solution is to set the pipe to non-blocking, and do everything
    #  in a single thread.
    # TODO: maybe revisit if ever changing to paired unidirectional pipes.
    pipe.Set_Nonblocking()
   

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
                keyboard_listener.Start()

            else:
                x4_has_focus = False
                # Stop the keyboard listener when tabbed out if it is running.
                keyboard_listener.Stop()
                # When x4 loses focus, assume all pressed keys are released
                # upon returning to x4. This addresses the common case of
                # alt-tabbing out (which leaves alt as pressed when clicking
                # back into x4 otherwise).
                # An alternate solution would be to capture all keys even
                # when x4 lacks focus, but while that was tried and worked,
                # it was distasteful.
                # Clear key states.
                combo_processor.Reset_State()
            

            # Try to read any data.
            message = pipe.Read()
            if message != None:
                print('Received: ' + message)

                # Ignore pings; they were just testing the pipe.
                if message == 'ping':
                    pass

                # Update the key list.
                elif message.startswith('setkeys:'):
                    # Toss the prefix.
                    message = message.replace('setkeys:', '')

                    # Get the new compiled combos.
                    combo_processor.Update_Combos(message)
                    print('Updated combos to: {}'.format(message))

                    # TODO: if all keys are unregistered, kill off this thread
                    # so it returns to waiting for pipe connection, and the
                    # key capture subthread is no longer running.
                    # Would just need to check for empty combo specs, and
                    # throw a pipe error exception (as expected by
                    # Server_Thread to reboot this module).
                

            # If anything is in the key_buffer, process into key combos.
            key_buffer = keyboard_listener.Retrieve_Key_Buffer()
            if key_buffer:
                if verbosity >= 2:
                    print('Processing: {}'.format(key_buffer))

                # Process the keys, updating what is pressed and getting any
                # matched combos.
                matched_combos = combo_processor.Process_Key_Events(key_buffer)
            
                # Start transmitting.
                for combo in matched_combos:
                    # Transmit to x4.
                    # Note: this doesn't put the '$' back for now, since that
                    # is easier to add in x4 than remove afterwards.
                    if verbosity >= 1:
                        print('Sending: ' + combo)
                    pipe.Write(combo)


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
        keyboard_listener.Stop()
    return


def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Pick some keys to capture.
    # Some given as MD registered string combos, some as ego keycodes.
    # 286 is shift-a, 82 is numpad 0.
    keys = 'setkeys:' + ';'.join([
            '$a onPress',
            '$a onRepeat',
            '$a onRelease',
            '$shift_l a onPress',
            '$shift_l s onPress',
            '$ctrl_l d onPress',
            '$alt_r f onPress',
            '$code 1 286 0 onPress',
            '$code 1 82 0 onPress',
        ]) + ';'
    pipe.Write(keys)

    # Capture a few characters.
    for _ in range(50):
        char = pipe.Read()
        print(char)
        pipe.Write('ack')
            
    return


# Scancode dict.
# This will map from windows vk codes to keyboard scancodes.
vk_scancode_mapping = {}


class Key_Event:
    '''
    Container for information about a key press or release event.
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
        return self.name + (' down' if self.pressed else ' up')
    def __str__(self):
        return repr(self)


class Keyboard_Listener():
    '''
    Class for listening to keyboard inputs.  Wraps pynput's listerner with
    extra functionality, buffering, and correction for missing info
    (notably up/down event annotation and key scancodes.
    '''
    def __init__(self):
        # Set up the keyboard listener.

        # Buffer of Key_Events. Index 0 is oldest press.
        # TODO: rethink buffer limit; it is mostly for safety, but if ever
        # hit it will cause problems with detecting key releases (eg. set
        # of held keys may have false state).
        self.key_buffer = []
        self.max_keys_buffered = 50

        # The listener thread itself.
        self.listener_thread = None


    def Retrieve_Key_Buffer(self):
        '''
        Returns the current contents of the key buffer, and empty the buffer.
        '''
        # Grab everything out of the key_buffer in one step, to play
        # more nicely with threading (assume interruption at any time).
        # Just do this with rebinding.
        ret_val = self.key_buffer
        self.key_buffer = []
        return ret_val

    # Capture key presses into a queue.
    def Buffer_Presses(self, key_object):
        '''
        Function to be called by the key listener on button presses.
        Kept super simple, due to pynput warning about long callbacks.
        '''
        if len(self.key_buffer) < self.max_keys_buffered:
            self.key_buffer.append( Key_Event(key_object, True))
        return
    
    def Buffer_Releases(self, key_object):
        '''
        Function to be called by the key listener on button releases.
        Kept super simple, due to pynput warning about long callbacks.
        '''
        if len(self.key_buffer) < self.max_keys_buffered:
            self.key_buffer.append( Key_Event(key_object, False))
        return

    def Event_Precheck(self, msg, data):
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


    def Start(self):
        '''
        Start up the keyboard listener thread if it isn't running already.
        '''
        # Return early if a thread is already set up.
        if self.listener_thread:
            return

        print('Starting keyboard listener')
        # Start the listener thread.
        self.listener_thread = keyboard.Listener(
            on_press   = self.Buffer_Presses,
            on_release = self.Buffer_Releases,
            win32_event_filter = self.Event_Precheck)

        self.listener_thread.start()
        return


    def Stop(self):
        '''
        Stop any currently running keyboard listener, and clears any
        currently buffered keys.
        '''
        if self.listener_thread:
            print('Stopping keyboard listener')
            self.listener_thread.stop()
            self.key_buffer.clear()
            # Can't reuse these threads, so just release and start a fresh
            # one when needed.
            self.listener_thread = None
        return


class Key_Combo:
    '''
    A key combination to listen for, as requested by x4.

    Attributes:
    * name
      - Name of the combo, as sent from x4.
    * key_codes
      - List of scancodes for this combo.
    * event
      - String, key event to look for.
      - onPress, onRelease, onRepeat
    * mod_flags
      - Int, 1-hot vector signifying which modifier keys are used in
        this combo.
      - Ordering of bits depends on order of "_mod_keys" list.
    * active
      - Bool, if this combo is currently active: was pressed and has not
        yet been released.
    '''
    def __init__(self, name, key_codes, event):
        self.name = name
        self.key_codes = key_codes
        self.event = event
        self.active = False

        # Set modifier flags here.
        # Code; starts at 0, gets bits set.
        self.mod_flags = 0
        # Check each modifier.
        for index, mod_key in enumerate(_mod_keycodes):
            if mod_key in key_codes:
                # Set a bit for this position.
                self.mod_flags += (1 << index)
        return


class Key_Combo_Processor:
    '''
    Process key combos, including parsing messages from x4 which set
    the combos to look for, and checking captured key presses for
    matches to these combos.

    Atteributes:
    * key_combo_list
      - List of Key_Combo objects being checked.
    * keys_in_combos
      - List of key scancodes involved in the combos, along with all
        modifier keys, to be used for filtering out don't-care events.
    * keys_down
      - List of scancodes that were pressed but not released yet.
    '''
    def __init__(self):
        # Recorded combos.
        self.key_combo_list = []
        
        # Set of keycodes involved in any combos, and modifiers.
        self.keys_in_combos = set()

        # Set of keys (Key or KeyCode) in a pressed state.
        # Updated when key_buffer is processed.
        # Note: only tracks keys of interest to the combos. Assumes combos
        # will not be changing often enough to worry about tracking unused
        # keys that might be used in the future.
        self.keys_down = set()
        return

    def Reset_State(self):
        '''
        Reset key states, for use when x4 loses focus and the keyboard
        listener has stopped, which will cause state to be invalid.
        '''
        # Set all combos as inactive.
        for combo in self.key_combo_list:
            combo.active = False
        # Clear held keys.
        self.keys_down.clear()
        return


    def Update_Combos(self, message):
        '''
        From a suitable "setkeys:" message, compile into the pynput
        key objects it represents, and update the watched-for combos.
        Overwrites any prior recorded combos.
        '''
        # Don't reuse old combos; each message should be a fully complete
        # list of currently desired combos.
        self.key_combo_list.clear()
        self.keys_in_combos.clear()

        # If all key/combos have been cleared, the rest of the message is blank.
        if not message:
            return

        # Expect each key combo to be prefixed with '$' and end with
        #  ';'.  Can separate on ';$', ignoring first and last char.
        # Note: any '$' or ';' in the combo itself is fine, since they
        #  will always be required to be space separated, and so won't
        #  get matched here.
        combos_requested = message[1:-1].split(';$')
        
        # Compile message strings to codes.
        for combo_string in combos_requested:
            # Collect the combo groups; each combo_string may make multiple,
            #  in cases where ambiguous modifier keys are uniquified
            #  (eg. 'ctrl' to 'ctrl_r' and 'ctrl_l' versions).
            # Skip any with errors.
            try:
                self.key_combo_list += self.Compile_Combo(combo_string)
            except Exception as ex:
                print('Error when handling combo {}, exception: {}'.format(combo_string, ex))
                continue

        # Update the list of keys to watch.
        for combo in self.key_combo_list:
            self.keys_in_combos.update(combo.key_codes)
        # Include modifiers always, left/right variations.
        self.keys_in_combos.update(_mod_keycodes)

        return


    def Compile_Combo(self, combo_msg):
        '''
        Translates a key/combo string from x4 into key scancode lists, 
        with generic shift-alt-ctrl keys being uniquified into left/right
        versions.

        Returns a list of Key_Combo objects.
        Throws an exception on unrecognized key names.
        '''
        # Pick off the suffixed event type.
        combo_string, event_name = combo_msg.rsplit(' ', 1)
        # Check it; skip if bad.
        if event_name not in ['onPress', 'onRelease', 'onRepeat']:
            print('Unrecognized event for combo: {}',format(combo_msg))
            return []

        # Process egosoft keycodes.
        # Aim is to unify their format with generic key combo strings, so
        # both can share the subsequent code.
        if combo_string.startswith('code '):
            key_name_list = self.Ego_Keycode_To_Combo(combo_string)
        else:
            # Break out the requested keys by spacing.
            key_name_list = combo_string.split()
    

        # For generic shift-alt-ctrl, uniquify them into left/right
        # versions. This could potentially generate up to 6 sub-combos
        # if all such keys are used.
        # Note: scancodes are not duplicated between left/right keys, so
        # this shouldn't have a danger of creating duplicate code combos.
        # Process combo_names into a new list of lists.
        # Seed this with a single empty list.
        key_name_list_list = [[]]
        for key_name in key_name_list:
            if key_name in ['shift','alt','ctrl']:

                # Duplicate the existing groups.
                l_combos = copy.deepcopy(key_name_list_list)
                r_combos = copy.deepcopy(key_name_list_list)

                # Append uniquified names.
                for groups, suffix in zip([l_combos, r_combos], ['_l','_r']):
                    for group in groups:
                        group.append(key_name + suffix)
                # Stick the new groups together again.
                key_name_list_list = l_combos + r_combos
            else:
                # Add the name to all groups.
                for group in key_name_list_list:
                    group.append(key_name)
                

        # Handle the key name to combo mapping.
        combo_list = []
        for key_name_list in key_name_list_list:
    
            # Map names to scancodes.
            # Skip empty key names, which may be the result of double
            # spacing in the message.
            # Unrecognized entries will have a dict key lookup error.
            scancodes = [_name_to_scancode_dict[x]
                            for x in key_name_list if x]

            # Pack into a Key_Combo and record.
            combo_list.append(Key_Combo(combo_msg, scancodes, event_name))

        return combo_list



    def Process_Key_Events(self, key_buffer):
        '''
        Processes raw key presses/releases captured into key_buffer,
        updating keys_down and matching to combos in combo_specs.
        Returns a list of combos names matched, using the original
        names from x4.

        * key_buffer
          - List of Keys that were captured since the last processing.
        '''
        matched_combo_names = []
    
        # Loop over the key events in recorded order.
        for key_event in key_buffer:

            # Use the scancode for the key tracking.
            key = key_event.code
        
            # If key is not of interest, ignore it.
            if key not in self.keys_in_combos:
                continue

            # Update pressed/released state.
            # Note: a raw modifier key (eg. shift_l) will be categorized as
            # needing itself held down, so update keys_down prior to
            # checking the combos to simplify following logic.
            if key_event.pressed:
                self.keys_down.add(key)
            elif key in self.keys_down:
                self.keys_down.remove(key)
            if verbosity >= 3:
                print('Keys down: {}'.format(self.keys_down))


            # The first pass logic will group combos into those
            # matched, held, unheld.
            # - Held: keys all pressed, other modifiers unpressed, but last key
            #   is not the latest key (should have had a press event earlier).
            # - Matched: as Held, but last key is the latest key.
            # - Unheld: everything else.
            # Checking these categories against the prior held combos will
            #  determine which ones are pressed (newly held), repeated
            #  (already held), released (no longer held).
            combos_held    = []
            combos_matched = []
            combos_unheld  = []

        
            # Get which modifier keys are currently held, and their
            #  corresponding category code.
            mod_flags = 0
            # Check each modifier.
            for index, mod_key in enumerate(_mod_keycodes):
                if mod_key in self.keys_down:
                    # Add a 1-hot bit.
                    mod_flags += (1 << index)


            # Check the combos for state updates.
            for combo in self.key_combo_list:

                # Determine if this combo is currently held.
                held = False
                # Make sure the mod_flags match.
                if combo.mod_flags == mod_flags:
                    # Check all keys being pressed.
                    held = all(x in self.keys_down for x in combo.key_codes)

                # Common case: not held and was not active, so idle.
                # Quick checking this, though somewhat redundant with
                # logic below.
                if not held and not combo.active:
                    continue

                # Determine if this combo is being triggered, eg. the last
                # combo key was pressed.
                triggered = held and key == combo.key_codes[-1]

                # Determine event trigger to match, and update combo active
                # state.
                if triggered:
                    # Was newly pressed if not already active, else it is
                    # being repeated.
                    event = 'onPress' if not combo.active else 'onRepeat'
                    combo.active = True
                elif held:
                    # Being held, but not a new trigger, so this can
                    # be ignored.
                    event = None
                else:
                    # Was released if it was formerly active.
                    event = 'onRelease' if combo.active else None
                    combo.active = False

                # If the event matches what the combo is looking for, then
                # can signal it back to x4.
                if combo.event == event:
                    matched_combo_names.append(combo.name)

        return matched_combo_names

    
    @staticmethod
    def Ego_Keycode_To_Combo(combo_string):
        '''
        Takes a combo_string from egosoft's input capture, and translates
        to a key combo. Returns a list with 1-3 items: 'shift' and 'ctrl'
        as optional modifiers, and the string name of the main key.

        The combo_string should begin with "code ".
        '''
        '''
        These come from using the ego menu system, and have the form:
            "code <input type> <key code> <sign>"
        For keyboard inputs, type is always 1, sign is always 0.
        So for now, the expected form is:
            "code 1 <key code> 0"

        Keycodes use standard keyboard scancodes.
        Modifiers for shift and ctrl are baked into the keycode's high byte:
            shift: 0x100
            ctrl : 0x400
        '''
        assert combo_string.startswith('code ')
    
        # Obtain the generic keyboard keycode, the third term.
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




# Dict mapping egosoft keycodes to key name strings understood by pynput.
# Ego keys appear to match this (excepting special shift/ctrl handling):
#  https://github.com/wgois/OIS/blob/master/includes/OISKeyboard.h
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
_mod_keys = ['alt_l','alt_r',
            'ctrl_l','ctrl_r',
            'shift_l','shift_r',]
# The associated integer key codes.
_mod_keycodes = [_name_to_scancode_dict[x] for x in _mod_keys]

