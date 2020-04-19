'''
Python side of measurement gathering.
'''
from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
import time
import threading

# Name of the pipe to use.
pipe_name = 'x4_perf'

# Flag to do a test run with the pipe client handled in python instead
# of x4.
test_python_client = 0


def main(args):
    '''
    Entry function for this server.
    Protocol: x4 sends some request, pipe server responds (or not) based
    on command.  The pipe server will never send messages on its own.
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

    # Var to hold the last tic time.
    last_tic = 0
           
    # FPS counter.
    # Goal here is to give a smoothed fps over time.
    fps_counter = FPS_Counter(window = 60)

    # Script counter, just for organization.
    # Keys match what is sent from x4.
    ai_counters = {
        '$aicommand'       : Count_Storage(type = 'Command'),
        '$aiaction'        : Count_Storage(type = 'Action'),
        '$aiscript'        : Count_Storage(type = 'Script'),
        '$aielement'       : Count_Storage(type = 'Element'),
        '$aiscriptline'    : Count_Storage(type = 'Script Line'),
        '$aiscriptlinesum' : Count_Storage(type = 'Script Line Sum'),
    }
    
    while 1:        
        # Blocking wait for a message from x4.
        message = pipe.Read()

        if test_python_client:
            print(pipe_name + ' server got: ' + message)

        # Ignore any setup pings.
        if message == 'ping':
            continue
        
        try:
            # First term is the command.
            command, args = message.split(';', 1)
       
            if command == 'update':

                # args are key:value pairs.
                # Semicolon separated, with an ending semicolon.
                # Split, toss the last blank.
                kv_pairs = args.split(';')[0:-1]

                for counter in ai_counters.values():
                    counter.Clear()

                # Process them into a dict of strings.
                # Note: keys are expected to start with $.
                data = {}
                for kv_pair in kv_pairs:
                    key, value = kv_pair.split(':')

                    # AI state will be handed off.
                    # These have the prefix added before a dot.
                    prefix = key.split('.', 1)[0]
                    if prefix in ai_counters:
                        subkey = key.split('.', 1)[1]
                        ai_counters[prefix].Set(subkey, value)
                    else:
                        data[key] = value
                        
                # Print the scripts, if any recorded.
                for counter in ai_counters.values():
                    counter.Print(20)

                # Do data analysis.
                # Several of these will depend on the in-game timestamp.
                gametime = float(data['$gametime'])

                # Update the fps counter/smoother.
                fps_counter.Update(gametime, float(data['$fps']))
                # Print the smoothed value.
                fps_counter.Print()


            else:
                print('Error:' + pipe_name + ' unrecognized command: ' + message)

        except Exception as ex:
            if test_python_client:
                raise ex
            #print(ex)
            print('Error in processing: {}'.format(message))

                        
        # TODO: maybe use time.sleep(?) for a bit if ever switching to
        # non-blocking reads.
    return


class FPS_Counter:
    '''
    Stores fps samples, and produces a smoothed value over time, since
    the in-game count fluctuated wildely each second.

    * samples
      - List of tuples of (gametime, fps count). Newest is first.
    * running_sum
      - Sum of fps counts, to speed up averaging.
      - Samples are assumed to arrive at a regular rate, eg. every second,
        as all will be treated as equally weighted.
      - Used to slightly speed up compute with many samples.
    * window
      - Float, how many seconds back to set the smoothing window for.
      - Samples older than this window will be removed.
    '''
    def __init__(self, window = 5):
        self.samples = []
        self.running_sum = 0
        self.window = window
        return

    def Update(self, gametime, fps):
        '''
        Record a new fps sample at the given gametime.
        '''
        self.samples.insert(0, (gametime, fps))
        self.running_sum += fps

        # Prune out old samples.
        oldest = gametime - self.window
        samples = self.samples
        # Go backwards, removing items until something is new enough.
        for i in reversed(range(len(samples))):
            if samples[i][0] < oldest:
                self.running_sum -= samples[i][1]
                samples.pop(-1)
            else:
                break
        return

    def Get_FPS(self):
        '''
        Return the current averaged fps.
        '''
        return self.running_sum / len(self.samples)

    def Print(self):
        '''
        Print a line with current state.
        '''
        samples = self.samples
        # Give some protection against too few samples.
        msg = 'fps: {:.1f} || over {:.1f}s: {:.1f}  (min: {:.1f}, max: {:.1f})'.format(
            # Latest sample.
            samples[0][1] if samples else 0,
            # Could give sampling window, or actual sample stretch; use latter.
            samples[0][0] - samples[-1][0] if len(samples) >= 2 else 0,
            # Average.
            self.running_sum / len(samples) if samples else 0,
            # Min and max over the range.
            min(x[1] for x in samples) if samples else 0,
            max(x[1] for x in samples) if samples else 0,
            )
        print(msg)
        return
    

class Count_Storage:
    '''
    Track the counts of things of some sort.

    * type
      - String, descriptive type of what's being counted, eg. command or action.
    * counts
      - Dict, keyed by command name, holding the command count.
    '''
    def __init__(self, type = ''):
        self.type = type
        self.counts = {}

    def Clear(self):
        self.counts.clear()

    def Set(self, name, count):
        self.counts[name] = float(count)

    def Print(self, top = 5):
        '''
        Prints the top 5 (or however many) most frequent counts.
        Does nothing if no counts known.
        '''
        if not self.counts:
            return

        lines = []
        remaining = top
        for script, count in sorted(self.counts.items(), key = lambda x: x[1], reverse = True):
            # Give spacing so the printout aligns somewhat.
            lines.append('{:<40} : {:5}'.format(script, count))
            remaining -= 1
            if not remaining:
                break
            
        msg = self.type + 's: {}\n'.format(sum(self.counts.values()))
        msg += self.type + ' counts (top {})\n'.format(top)
        for line in lines:
            msg += '  '+line+'\n'
        print(msg)
        return


def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Example messages.
    messages = [
        'update;$fps:25;$gametime:0;',
        'update;$fps:20;$gametime:1;',
        'update;$fps:27;$gametime:2;',
        'update;$fps:24;$gametime:3;',
        'update;$fps:17;$gametime:4;',
        'update;$fps:24;$gametime:5;',
        'update;$fps:29;$gametime:6;',
        'update;$fps:25;$gametime:7;',
        'update;$fps:26;$gametime:8;',
        'update;$fps:25;$gametime:9;$aicommand.move:20;$aicommand.fight:30;',
        'update;$fps:21;$gametime:10;$aiaction.dock:20;$aiaction.flying:30;',
        ]

    # Just transmit; expect no responses for now.
    for message in messages:
        pipe.Write(message)

    return
