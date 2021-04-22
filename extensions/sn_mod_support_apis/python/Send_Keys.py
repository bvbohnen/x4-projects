'''
Server which will capture select keyboard key presses, and will
signal them to x4 accordingly, to be bound x4-side to MD cues.

Uses the pynput package (not included with anaconda or standard python).

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


import sys
import time
import threading
import copy
from collections import defaultdict

# This will be specific to windows for now.
if not sys.platform == 'win32':
    raise Exception("Only windows supported at this time.")

#import win32file
import win32api

from pynput import keyboard
from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
# Can use this to know if x4 has focus.
from win32gui import GetWindowText, GetForegroundWindow

# Name of the pipe to use.
pipe_name = 'x4_keys'

# Verbosity level of console window messages.
verbosity = 1

# Expected window title, for when this captures keys.
# Normally x4, but changes for python testing.
# For python, there may be a path prefix, so this will just check the
# final part of the window title.
window_title = 'X4'


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
    # Set up the pipe and connect to x4.
    pipe = Pipe_Server(pipe_name)
        
    # Enable test mode if requested.
    if args['test']:
        # TODO: make more robust, eg. work with cmd.
        window_title = 'python.exe'
        # Set up the reader in another thread.
        # Note: if doing this from a console window, pynput prevents ctrl-c
        # exits, but ctrl-pause/break will work.
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
            # This will grab as much as it can get, so response handling
            # doesn't bog down when a lot of acks come back (since this
            # is checked on a timer, where each interval can send several
            # key events, eg. when keys are held down).
            message = pipe.Read()
            while message != None:
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

                # Try to get another message.
                message = pipe.Read()
                

            # If anything is in the key_buffer, process into key combos.
            key_buffer = keyboard_listener.Retrieve_Key_Buffer()
            if key_buffer:
                if verbosity >= 2:
                    print('Processing: {}'.format(key_buffer))

                # Process the keys, updating what is pressed and getting any
                # matched combos.
                matched_combos = combo_processor.Process_Key_Events(key_buffer)

                # Only send messages if there was a match; x4 4.0 started
                # sometimes going into an error loop (on ~25% of reloads)
                # where all key presses with empty messages caused a pipe
                # error. TODO: maybe track down the intermittent problem
                # more specifically.
                if matched_combos:
                    # Lump into a single message, to reduce overhead on the x4
                    # side (since it limits signals per frame and can lag when
                    # handling key repetitions).
                    # Note: this doesn't put the '$' back for now, since that
                    # is easier to add in x4 than remove afterwards.
                    message = ';'.join(matched_combos)

                    # Debug printout.
                    if verbosity >= 1:
                        for combo in matched_combos:
                            print('Sending: ' + combo)

                    # Transmit to x4.
                    pipe.Write(message)


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
    # Note: leftshift-a should send '$shift_l a onPress' and '$code 1 286 0 onPress'
    # but not '$a onPress'.
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
        print(f'test received: {char}')
        pipe.Write('ack')
            
    return



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
    * code
      - Int, keyboard scancode of the key that was pressed, as decided
        by windows, adding 0x80 for extended keys.
    * pressed
      - Bool, if True the key was pressed, else the key was released.
    '''
    def __init__(self, key_object, scancode, pressed = None):
        self.code = scancode
        self.pressed = pressed

        # The key vk is either in 'vk' or 'value.vk'.
        # TODO: special handling for numpad_enter; maybe pick name
        # from the scancode.
        if hasattr(key_object, 'vk'):
            self.vk = key_object.vk
            self.name = key_object.char
        else:
            self.vk = key_object.value.vk
            self.name = key_object.name

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

        # The last scancode seen, to transfer from Event_Precheck 
        # to the Buffer_X calls.
        # Note: in testing, there were never observed to Event_Prechecks
        # before the Buffer call, so hopefully this will never mismatch
        # a scancode to the wrong key.
        self.last_scancode = None

        return


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
            self.key_buffer.append( Key_Event(key_object, self.last_scancode, True))
        return
    
    def Buffer_Releases(self, key_object):
        '''
        Function to be called by the key listener on button releases.
        Kept super simple, due to pynput warning about long callbacks.
        '''
        if len(self.key_buffer) < self.max_keys_buffered:
            self.key_buffer.append( Key_Event(key_object, self.last_scancode, False))
        return

    def Event_Precheck(self, msg, data):
        '''
        Function to be called whenever pynput detects an input event.
        Should return True to continue processing the event, else False.
        From a glance at pynput source, this might be called significantly
        ahead of the on_press and on_release callbacks.

        This is mainly used to try to get more key information, since normal
        pynput KeyPress objects use windows vk codes which don't distinguish
        extended keys.
        '''
        # 'data' is a dict with keys matching those in KBLLHOOKSTRUCT:
        # https://docs.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct

        # Determine the actual x4-style scancode.
        # This is the windows base scancode from the struct, offset by an
        # extra 0x80 if it is an extended key.
        self.last_scancode = data.scanCode
        if data.flags & 1:
            self.last_scancode += 0x80
        
        if verbosity >= 3:
            print(f'data.vkCode: {hex(data.vkCode)}({data.vkCode}),'
                  f' data.scanCode: {hex(data.scanCode)}({data.scanCode}),'
                  f' data.flags: {hex(data.flags)}, scancode: '
                  f'{hex(self.last_scancode)}({self.last_scancode})')

        # Always process the key for now.
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
        for index, mod_key in enumerate(mod_key_scancode_list):
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
        self.keys_in_combos.update(mod_key_scancode_list)

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
            scancodes = [name_to_scancode_dict[x]
                            for x in key_name_list if x]

            # Pack into a Key_Combo and record.
            combo_list.append(Key_Combo(combo_msg, scancodes, event_name))

        return combo_list



    def Process_Key_Events(self, key_buffer):
        '''
        Processes raw key presses/releases captured into key_buffer,
        updating keys_down and matching to combos in combo_specs.
        Returns a list of combo names matched, using the original
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
                if verbosity >= 3:
                    print(f'Keycode {key} not in {self.keys_in_combos}')
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
                print('Keys down: {}'.format(self.keys_down if self.keys_down else ''))


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
            for index, mod_key in enumerate(mod_key_scancode_list):
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
        keyname = scancode_to_name_dict.get(keycode, None)
        # Error if the keyname not supported.
        if not keyname:
            raise Exception("Ego keycode {} not supported".format(keycode))
        combo.append(keyname)

        return combo



'''
Windows vk codes:
 https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes

Scancodes (Ego keys appear to match this)(only for standard english):
 https://github.com/wgois/OIS/blob/master/includes/OISKeyboard.h
 Note: in testing this appears to be bugged, with numlock/pause reversed.

Doc on windows input handling:
 https://docs.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input
Note: various keys, generally those on the numpad, will alias to each other.
These are distinguished by an "extended-key" flag.
" The extended keys consist of the ALT and CTRL keys on the right-hand side
of the keyboard; the INS, DEL, HOME, END, PAGE UP, PAGE DOWN, and arrow keys
in the clusters to the left of the numeric keypad; the NUM LOCK key; the BREAK
(CTRL+PAUSE) key; the PRINT SCRN key; and the divide (/) and ENTER keys in the
numeric keypad."

win32api.MapVirtualKey will translate a vk to a scancode, but the scancode
is always the non-extended version (eg. VK_HOME maps to the numpad7 scancode).

By observation, it appears the x4 scancodes that deal with extended
keys will use the non-extended scancode by default, and then set bit 8
for the extended flag.  Eg. VK_LCONTROL is 0x1D, VK_RCONTROL is 0x9D.
'''
# List of keys, windows virtual keycodes, scancodes, and string names.
# (Scancode mapping here is only for english.)
# Entries are tuples of:
# (win vk name, vk code, extended flag, english scancode, pynput/local name)
# TODO: remove scancodes; they are generated at runtime instead.
key_info_list = [
    ('VK_LBUTTON'            , 0x01, 0, None , None),
    ('VK_RBUTTON'            , 0x02, 0, None , None ),
    ('VK_CANCEL'             , 0x03, 1, None , 'break' ), # Sent with ctrl+pause as ctrl+break
    ('VK_MBUTTON'            , 0x04, 0, None , None ),
    ('VK_XBUTTON1'           , 0x05, 0, None , None ),
    ('VK_XBUTTON2'           , 0x06, 0, None , None ),
    ('VK_BACK'               , 0x08, 0, 0x0E , "backspace"),
    ('VK_TAB'                , 0x09, 0, 0x0F , "tab"),
    ('VK_CLEAR'              , 0x0C, 0, None , None ),
    ('VK_RETURN'             , 0x0D, 0, 0x1C , "enter"),
    # Ignore generic key modifiers; left/right versions are below, and
    # these get special handling in combo processing code.
    ('VK_SHIFT'              , 0x10, 0, None , None ),
    ('VK_CONTROL'            , 0x11, 0, None , None ),
    ('VK_MENU'               , 0x12, 0, None , None ), # Alt
    ('VK_PAUSE'              , 0x13, 0, 0x45 , "pause"), # MapVirtualKey returns 0 (for whatever reason)
    ('VK_CAPITAL'            , 0x14, 0, 0x3A , "caps_lock"),
    ('VK_ESCAPE'             , 0x1B, 0, 0x01 , "esc"),
    ('VK_SPACE'              , 0x20, 0, 0x39 , "space"),
    ('VK_PRIOR'              , 0x21, 1, 0xC9 , "page_up"),
    ('VK_NEXT'               , 0x22, 1, 0xD1 , "page_down"),
    ('VK_END'                , 0x23, 1, 0xCF , "end"),
    ('VK_HOME'               , 0x24, 1, 0xC7 , "home"),
    ('VK_LEFT'               , 0x25, 1, 0xCB , "left"),
    ('VK_UP'                 , 0x26, 1, 0xC8 , "up"),
    ('VK_RIGHT'              , 0x27, 1, 0xCD , "right"),
    ('VK_DOWN'               , 0x28, 1, 0xD0 , "down"),
    ('VK_SELECT'             , 0x29, 0, None , None ),
    ('VK_PRINT'              , 0x2A, 0, None , None ),
    ('VK_EXECUTE'            , 0x2B, 0, None , None ),
    ('VK_SNAPSHOT'           , 0x2C, 1, 0x54 , "printscreen"), # Maybe wrong scancode, but determined properly below.
    ('VK_INSERT'             , 0x2D, 1, 0xD2 , "insert"),
    ('VK_DELETE'             , 0x2E, 1, 0xD3 , "delete"),
    ('VK_HELP'               , 0x2F, 0, None , None ),
    ('VK_0'                  , 0x30, 0, 0x0B , "0"),           
    ('VK_1'                  , 0x31, 0, 0x02 , "1"),          
    ('VK_2'                  , 0x32, 0, 0x03 , "2"),          
    ('VK_3'                  , 0x33, 0, 0x04 , "3"),          
    ('VK_4'                  , 0x34, 0, 0x05 , "4"),          
    ('VK_5'                  , 0x35, 0, 0x06 , "5"),          
    ('VK_6'                  , 0x36, 0, 0x07 , "6"),          
    ('VK_7'                  , 0x37, 0, 0x08 , "7"),          
    ('VK_8'                  , 0x38, 0, 0x09 , "8"),          
    ('VK_9'                  , 0x39, 0, 0x0A , "9"),          
    ('VK_A'                  , 0x41, 0, 0x1E , "a"),
    ('VK_B'                  , 0x42, 0, 0x30 , "b"),
    ('VK_C'                  , 0x43, 0, 0x2E , "c"),
    ('VK_D'                  , 0x44, 0, 0x20 , "d"),
    ('VK_E'                  , 0x45, 0, 0x12 , "e"),
    ('VK_F'                  , 0x46, 0, 0x21 , "f"),
    ('VK_G'                  , 0x47, 0, 0x22 , "g"),
    ('VK_H'                  , 0x48, 0, 0x23 , "h"),
    ('VK_I'                  , 0x49, 0, 0x17 , "i"),
    ('VK_J'                  , 0x4A, 0, 0x24 , "j"),
    ('VK_K'                  , 0x4B, 0, 0x25 , "k"),
    ('VK_L'                  , 0x4C, 0, 0x26 , "l"),
    ('VK_M'                  , 0x4D, 0, 0x32 , "m"),
    ('VK_N'                  , 0x4E, 0, 0x31 , "n"),
    ('VK_O'                  , 0x4F, 0, 0x18 , "o"),
    ('VK_P'                  , 0x50, 0, 0x19 , "p"),
    ('VK_Q'                  , 0x51, 0, 0x10 , "q"),
    ('VK_R'                  , 0x52, 0, 0x13 , "r"),
    ('VK_S'                  , 0x53, 0, 0x1F , "s"),
    ('VK_T'                  , 0x54, 0, 0x14 , "t"),
    ('VK_U'                  , 0x55, 0, 0x16 , "u"),
    ('VK_V'                  , 0x56, 0, 0x2F , "v"),
    ('VK_W'                  , 0x57, 0, 0x11 , "w"),
    ('VK_X'                  , 0x58, 0, 0x2D , "x"),
    ('VK_Y'                  , 0x59, 0, 0x15 , "y"),
    ('VK_Z'                  , 0x5A, 0, 0x2C , "z"),
    ('VK_LWIN'               , 0x5B, 0, 0xDB , "win_l"),
    ('VK_RWIN'               , 0x5C, 0, 0xDC , "win_r"),
    ('VK_APPS'               , 0x5D, 0, None , None ),
    ('VK_SLEEP'              , 0x5F, 0, None , None ),
    ('VK_NUMPAD0'            , 0x60, 0, 0x52 , "num_0"),
    ('VK_NUMPAD1'            , 0x61, 0, 0x4F , "num_1"),
    ('VK_NUMPAD2'            , 0x62, 0, 0x50 , "num_2"),
    ('VK_NUMPAD3'            , 0x63, 0, 0x51 , "num_3"),
    ('VK_NUMPAD4'            , 0x64, 0, 0x4B , "num_4"),
    ('VK_NUMPAD5'            , 0x65, 0, 0x4C , "num_5"),
    ('VK_NUMPAD6'            , 0x66, 0, 0x4D , "num_6"),
    ('VK_NUMPAD7'            , 0x67, 0, 0x47 , "num_7"),
    ('VK_NUMPAD8'            , 0x68, 0, 0x48 , "num_8"),
    ('VK_NUMPAD9'            , 0x69, 0, 0x49 , "num_9"),
    ('VK_MULTIPL'            , 0x6A, 0, 0x37 , "num_*"),
    ('VK_ADD'                , 0x6B, 0, 0x4E , "num_+"),
    ('VK_SEPARATOR'          , 0x6C, 0, None , None ),
    ('VK_SUBTRACT'           , 0x6D, 0, 0x4A , "num_-"),
    ('VK_DECIMAL'            , 0x6E, 0, 0x53 , "num_."),
    ('VK_DIVIDE'             , 0x6F, 1, 0xB5 , "num_/"),
    ('VK_F1'                 , 0x70, 0, 0x3B , "f1", ),
    ('VK_F2'                 , 0x71, 0, 0x3C , "f2", ),
    ('VK_F3'                 , 0x72, 0, 0x3D , "f3", ),
    ('VK_F4'                 , 0x73, 0, 0x3E , "f4", ),
    ('VK_F5'                 , 0x74, 0, 0x3F , "f5", ),
    ('VK_F6'                 , 0x75, 0, 0x40 , "f6", ),
    ('VK_F7'                 , 0x76, 0, 0x41 , "f7", ),
    ('VK_F8'                 , 0x77, 0, 0x42 , "f8", ),
    ('VK_F9'                 , 0x78, 0, 0x43 , "f9", ),
    ('VK_F10'                , 0x79, 0, 0x44 , "f10"),
    ('VK_F11'                , 0x7A, 0, 0x57 , "f11"),
    ('VK_F12'                , 0x7B, 0, 0x58 , "f12"),
    ('VK_F13'                , 0x7C, 0, 0x64 , "f13"),
    ('VK_F14'                , 0x7D, 0, 0x65 , "f14"),
    ('VK_F15'                , 0x7E, 0, 0x66 , "f15"),
    ('VK_F16'                , 0x7F, 0, None , None ),
    ('VK_F17'                , 0x80, 0, None , None ),
    ('VK_F18'                , 0x81, 0, None , None ),
    ('VK_F19'                , 0x82, 0, None , None ),
    ('VK_F20'                , 0x83, 0, None , None ),
    ('VK_F21'                , 0x84, 0, None , None ),
    ('VK_F22'                , 0x85, 0, None , None ),
    ('VK_F23'                , 0x86, 0, None , None ),
    ('VK_F24'                , 0x87, 0, None , None ),
    ('VK_NUMLOCK'            , 0x90, 1, 0xC5 , "num_lock"), # Alias to pause
    ('VK_SCROLL'             , 0x91, 0, 0x46 , "scroll_lock"),
    ('VK_LSHIFT'             , 0xA0, 0, 0x2A , "shift_l"),
    ('VK_RSHIFT'             , 0xA1, 0, 0x36 , "shift_r"),
    ('VK_LCONTROL'           , 0xA2, 0, 0x1D , "ctrl_l"),
    ('VK_RCONTROL'           , 0xA3, 1, 0x9D , "ctrl_r"),
    ('VK_LMENU'              , 0xA4, 0, 0x38 , "alt_l"),
    ('VK_RMENU'              , 0xA5, 1, 0xB8 , "alt_r"),
    ('VK_BROWSER_BACK'       , 0xA6, 0, None , None ),
    ('VK_BROWSER_FORWARD'    , 0xA7, 0, None , None ),
    ('VK_BROWSER_REFRESH'    , 0xA8, 0, None , None ),
    ('VK_BROWSER_STOP'       , 0xA9, 0, None , None ),
    ('VK_BROWSER_SEARCH'     , 0xAA, 0, None , None ),
    ('VK_BROWSER_FAVORITES'  , 0xAB, 0, None , None ),
    ('VK_BROWSER_HOME'       , 0xAC, 0, None , None ),
    ('VK_VOLUME_MUTE'        , 0xAD, 0, None , None ),
    ('VK_VOLUME_DOWN'        , 0xAE, 0, None , None ),
    ('VK_VOLUME_UP'          , 0xAF, 0, None , None ),
    ('VK_MEDIA_NEXT_TRACK'   , 0xB0, 0, None , None ),
    ('VK_MEDIA_PREV_TRACK'   , 0xB1, 0, None , None ),
    ('VK_MEDIA_STOP'         , 0xB2, 0, None , None ),
    ('VK_MEDIA_PLAY_PAUSE'   , 0xB3, 0, None , None ),
    ('VK_LAUNCH_MAIL'        , 0xB4, 0, None , None ),
    ('VK_LAUNCH_MEDIA_SELECT', 0xB5, 0, None , None ),
    ('VK_LAUNCH_APP1'        , 0xB6, 0, None , None ),
    ('VK_LAUNCH_APP2'        , 0xB7, 0, None , None ),
    ('VK_OEM_1'              , 0xBA, 0, 0x27 , ";"),
    ('VK_OEM_PLUS'           , 0xBB, 0, 0x0D , "=", ),
    ('VK_OEM_COMMA'          , 0xBC, 0, 0x33 , ","),
    ('VK_OEM_MINUS'          , 0xBD, 0, 0x0C , "-"),
    ('VK_OEM_PERIOD'         , 0xBE, 0, 0x34 , "."),
    ('VK_OEM_2'              , 0xBF, 0, 0x35 , "/"),
    ('VK_OEM_3'              , 0xC0, 0, 0x29 , "`"),
    ('VK_OEM_4'              , 0xDB, 0, 0x1A , "["),
    ('VK_OEM_5'              , 0xDC, 0, 0x2B , "\\"),
    ('VK_OEM_6'              , 0xDD, 0, 0x1B , "]"),
    ('VK_OEM_7'              , 0xDE, 0, 0x28 , "'"),
    ('VK_OEM_8'              , 0xDF, 0, None , None ),
    ('VK_OEM_102'            , 0xE2, 0, 0x56 , "oem102"),
    ('VK_PROCESSKEY'         , 0xE5, 0, None , None ),
    ('VK_PACKET'             , 0xE7, 0, None , None ),
    ('VK_ATTN'               , 0xF6, 0, None , None ),
    ('VK_CRSEL'              , 0xF7, 0, None , None ),
    ('VK_EXSEL'              , 0xF8, 0, None , None ),
    ('VK_EREOF'              , 0xF9, 0, None , None ),
    ('VK_PLAY'               , 0xFA, 0, None , None ),
    ('VK_ZOOM'               , 0xFB, 0, None , None ),
    ('VK_NONAME'             , 0xFC, 0, None , None ),
    ('VK_PA1'                , 0xFD, 0, None , None ),
    ('VK_OEM_CLEAR'          , 0xFE, 0, None , None ),
    # Fake entry for numpad enter, which has no vk of its own.
    ('NUMPAD_ENTER'          ,0x100, 1, 0x9C , "num_enter", ),
    ]

# TODO:
# Map vk to a display name, supporting other languages.
# https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getkeynametexta

# Dict mapping vk codes (from pynput) to scancodes (from x4).
vk_to_scancode_dict = {}

# Dict mapping scancodes to key name strings understood by pynput,
# and hence allowed by md side key names.
# TODO: maybe think about the language issue, but most users will use the
# in-game key mapper, and md is english anyway, so this isn't very important
# for now.
scancode_to_name_dict = {}

# Reversal of the above, to map defined names to scancodes.
# Where a name is reused, the lowerscancode is kept.
# (Iterates in reverse sorted order, so lower scancode wins.)
name_to_scancode_dict = {}

# List of modifier key scancodes, left and right versions.
mod_key_scancode_list = None


def Key_Init():
    '''
    Initialize data related to vks and scancodes for use at runtime.
    '''
    # Mapping of vk names to their vk codes, for convenience.
    vk_name_to_code_dict = {}

    # Set of vk codes that map to extended keys.
    vks_that_are_extended_set = set(x[0] for x in key_info_list if x[2])

    # Match vk codes to scancodes. Just do this once here, to avoid having to
    # keep doing it during runtime.
    for vkname, vk, extended, eng_scancode, local_name in key_info_list:

        # Skip unsupported keys for now.
        if not local_name:
            continue

        # For portability across languages and keyboard layouts, use windows
        # api to translate this.
        # Note: the api function always returns the non-extended scancode.
        # (See notes further below on the extended-key flag in windows.)
        # https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-mapvirtualkeya

        # Note: apparently MapVirtualKey is problematic for Pause and
        # returns 0, so handle manually.
        # (First google result says its a bug: https://blog.molecular-matters.com/2011/09/05/properly-handling-keyboard-input/ )
        if vkname == 'VK_PAUSE':
            scancode = eng_scancode
        else:
            # Special handling of numpad_enter; treat it like enter for
            # scancode lookup.
            this_vk = vk
            if vkname == 'NUMPAD_ENTER':
                this_vk = vk_name_to_code_dict['VK_RETURN']
            scancode = win32api.MapVirtualKey(this_vk, 0)

        # If this vk is an extended-key, set the high bit.
        if extended:
            scancode += 0x80

        vk_name_to_code_dict[vkname] = vk
        vk_to_scancode_dict[vk] = scancode
        scancode_to_name_dict[scancode] = local_name
        name_to_scancode_dict[local_name] = scancode

    # The modifier keys to always track.
    global mod_key_scancode_list
    mod_key_scancode_list = [name_to_scancode_dict[x] for x in [
        'alt_l','alt_r','ctrl_l','ctrl_r','shift_l','shift_r',]]
    return

Key_Init()
