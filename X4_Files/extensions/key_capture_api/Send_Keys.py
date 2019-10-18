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

from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
from pynput import keyboard
import time
import threading
# Can use this to know if x4 has focus.
from win32gui import GetWindowText, GetForegroundWindow
import win32file
import copy
from collections import defaultdict

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


# List of modifier key names, used a couple places to categorize key combos.
# These are left/right versions, as well as the plain version, since
# 'shift' was observed to be returned plain for left-shift.
mod_keys = ['alt','alt_l','alt_r','alt_gr',
            'ctrl','ctrl_l','ctrl_r',
            'shift','shift_l','shift_r']
# The associated integer key codes, in order.
mod_keycodes = [getattr(keyboard.Key, x).value.vk for x in mod_keys]


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

    # Start the keyboard listener after client connect, in case it
    # never connects.
    Start_Keyboard_Listener()

    # Announce this as global, since it gets reassigned at one point.
    global key_buffer
    
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

    # Flag to indicate if x4 has focus.
    global x4_has_focus
        
    
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

    while 1:
        
        # Determine if x4 is the focused window.
        # Get the window title of whatever window has focus.
        focused_window_title = GetWindowText(GetForegroundWindow())
        # Ignore if not the wanted window.
        # Only check the end of the title, to avoid paths in the cmd window
        # when testing in python.
        if focused_window_title.endswith(window_title):
            x4_has_focus = True
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
            
        # TODO: shut down the keyboard listener thread when x4 loses
        # focus, and restart it on focus gain, so it isn't running
        # when x4 tabbed out.
        
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

# The listener thread itself.
listener_thread = None

# Global flag for it x4 has focus.
# Updated periodically in primary server loop.
# Probably doesn't matter much if True or False, but default True
# so keys start capturing sooner if x4 reloaded and server is
# rebooting.
x4_has_focus = True

# Capture key presses into a queue.
def Buffer_Presses(key):
    '''
    Function to be called by the key listener on button presses.
    Kept super simple, due to pynput warning about long callbacks.
    '''
    # Stick in a 1 for pressed.
    if x4_has_focus and len(key_buffer) < max_keys_buffered:
        key_buffer.append((1, key))
    return
    
def Buffer_Releases(key):
    '''
    Function to be called by the key listener on button releases.
    Kept super simple, due to pynput warning about long callbacks.
    '''
    # Stick in a 0 for released.
    if x4_has_focus and len(key_buffer) < max_keys_buffered:
        key_buffer.append((0, key))
    return

def Start_Keyboard_Listener():
    '''
    Start up the keyboard listener thread if it isn't running already.
    If main() exits and restarts, the same listener thread should still
    be running and will be reused.
    This extra step was added when multiple server restarts led to
    pynput getting in some buggy state where it only returned codes
    instead of letters (eg. b'\x01' instead of 'a').
    '''
    global listener_thread

    # If the thread is running, just clear the buffer.
    if listener_thread != None:
        print('Reusing running keyboard listener')
        key_buffer.clear()

    else:
        print('Starting keyboard listener')
        # Start the listener thread.
        listener_thread = keyboard.Listener(
            on_press   = Buffer_Presses,
            on_release = Buffer_Releases)

        listener_thread.start()
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
        for combo in Compile_Combo(combo_string):
            combo_specs.append((combo_string, combo))


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
    '''

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
    encoded_combo_list = []
    for combo in combo_list:
    
        # Set up a list for these keys, and add to the list of combos.
        encoded_combo = []
    
        # Map to Key and KeyCode objects.
        for key_name in combo:
    
            # If empty, something weird happened like double spacing in the
            #  user input. Treat that as okay, but ignore this split element.
            if not key_name:
                continue
    
            # TODO: error detection if not understood.
    
            # Single letters are alphanumeric. Use as-is.
            # Note: wrapping in a KeyCode will just have this key_name
            # placed in its char field, which is pointless.
            if len(key_name) == 1:
                key = key_name
    
            # Longer names will map to an integer code.
            else:
                # Look up the enumerator entry, get its value, a KeyCode.
                # From the KeyCode, use the vk attribute for the integer
                # key value.
                key = getattr(keyboard.Key, key_name).value.vk
    
            encoded_combo.append(key)
            
        # It is possible this encoded_combo is already present, due
        #  to modifier keycode aliasing.
        # Only record the new combo if unique.
        if not any(encoded_combo == x for x in encoded_combo_list):
            encoded_combo_list.append(encoded_combo)
            
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
    for pressed1_releases0, key in key_buffer:

        # Translate to a string or integer.
        # This is a bit awkward; KeyCode put through str() returns an 
        # extra set of single quotes (for whatever reason), so need to
        # take care how this is done.
        if isinstance(key, keyboard.KeyCode):
            key = key.char
        elif isinstance(key, keyboard.Key):
            key = key.value.vk
        else:
            # Probably shouldn't be here ever.
            # TODO: maybe assert, but skip to be safe.
            continue
        

        # If key is not of interest, ignore it.
        if key not in keys_in_combos:
            continue

        # Update pressed/released state.
        # Note: a raw modifier key (eg. shift_l) will be categorized as
        # needing itself held down, so update keys_down prior to
        # checking the combos.
        if pressed1_releases0 == 1:
            keys_down.add(key)
        elif key in keys_down:
            keys_down.remove(key)


        # On press, match up against combos.
        if pressed1_releases0 == 1:

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
                #  for now. TODO: fix elsewhere (eg. prune those keys
                #  from the combo lists after category set).
                if all(x in keys_down for x in combo[1:]):
                    # This is a combo match.
                    matched_combo_names.append(name)
                        

    return matched_combo_names



def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Pick some keys to capture.
    keys = 'setkeys:$a;$shift_l s;$ctrl_l d;$alt_r f;'
    pipe.Write(keys)

    # Capture a few characters.
    for _ in range(50):
        # In theory this is one message, but appears to be buggy.
        char = pipe.Read()
        print(char)
        pipe.Write('ack')
            
    return