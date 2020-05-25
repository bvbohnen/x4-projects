'''
Python side of measurement gathering.
'''
from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
import time
import threading
import json
from pathlib import Path
import configparser

this_dir = Path(__file__).resolve().parent
main_dir = this_dir.parent

# Name of the pipe to use.
pipe_name = 'x4_script_profile'

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
        
    # Load settings from the ini file(s).
    # Defaults are in settings_defaults.ini
    # User overrides are in settings.ini (may or may not exist).
    config = configparser.ConfigParser()
    config.read([main_dir/'config_defaults.ini', main_dir/'config.ini'])

    # Extract values.
    report_file_name = config['Server']['report_file']
    # TODO: others

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
        '$ai_command'         : Count_Storage(type = 'AI Command'),
        '$ai_action'          : Count_Storage(type = 'AI Action'),
        '$ai_script'          : Count_Storage(type = 'AI Script'),
        '$ai_element'         : Count_Storage(type = 'AI Element'),
        '$ai_scriptline'      : Count_Storage(type = 'AI Script Line'),
        '$ai_scriptline_hits' : Count_Storage(type = 'AI Script Blocking Line Hit'),
        '$md_cue_hits'        : Count_Storage(type = 'MD Cue/Lib Action Hit'),
        # New info, combines md and ai.
        'event_counts'       : Count_Storage(type = 'Event Count'),
    }

    # Path metrics trackers.
    # Separate md and ai.
    path_metrics = {
        'ai' : Path_Metrics(type = 'AI Path Time'),
        'md' : Path_Metrics(type = 'MD Path Time'),
        }

    # General dict of game state data, most recently sent.
    # 'fps','gametime', etc.
    state_data = {}
    
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
       
            # Generic current state update.
            if command == 'update':
                
                # args are key:value pairs.
                # Semicolon separated, with an ending semicolon.
                # Split, toss the last blank.
                kv_pairs = args.split(';')[0:-1]

                # Process them into a dict of strings.
                # Note: keys are expected to start with $.
                # Delay printout of fps, since gametime might show up
                # later in the message.
                print_fps = False
                for kv_pair in kv_pairs:
                    key, value = kv_pair.split(':')

                    # Explicitly handle cases, for casting and clarity.
                    # TODO: maybe just special handling for fps, generic
                    # for others.
                    if key == '$gametime':
                        state_data['gametime'] = float(value)

                    elif key == 'path_metrics_timespan':
                        state_data['path_metrics_timespan'] = float(value)

                    elif key == '$fps':
                        state_data['fps'] = float(value)
                        print_fps = True
                        
                    # TODO: other stuff.

                if print_fps:
                    # Update the fps counter/smoother.
                    fps_counter.Update(state_data['gametime'], state_data['fps'])
                    # Print the smoothed value.
                    fps_counter.Print()

                                        
                # Get the in-game systemtime.
                #print('$systemtime (H,M,S): {}'.format(data['$systemtime']))
                

            elif command == 'ai_metrics':

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
                        # Skip for now. Dont want to message spam, also
                        # don't want complete failure.
                        pass
                        
                # Print the scripts, if any recorded.
                for counter in ai_counters.values():
                    counter.Print(20)

            # Event counters switched to lumping everything in one command.
            elif command == 'event_counts':
                counter = ai_counters['event_counts']
                counter.Clear()

                # Split, toss the last blank.
                kv_pairs = args.split(';')[0:-1]
                for kv_pair in kv_pairs:
                    key, value = kv_pair.split(':')
                    counter.Set(key, value)
                counter.Print(20)
                

            # Path times are more complex.
            elif command == 'path_times':

                # This will hold data on both md and ai scripts.
                # However, for nicer printout, they will get split up here.
                # Start with resetting data.
                for tracker in path_metrics.values():
                    tracker.Clear()
                
                # Split, toss the last blank.
                kv_pairs = args.split(';')[0:-1]
                for kv_pair in kv_pairs:
                    key, value = kv_pair.split(':')
                    # Separate based on key starting with 'ai' or 'md'.
                    if key[0] == 'a':
                        path_metrics['ai'].Set(key, value)
                    else:
                        path_metrics['md'].Set(key, value)

                # For path_times, there is an empty cue which can be used
                # to adjust for the overhead of gathering systemtime.
                empty_cue_time = path_metrics['md'].metrics.get(
                    'md.SN_Measure_Perf.Empty_Cue,entry 101,exit 102')
                if empty_cue_time == None:
                    print('Error: failed to find Empty_Cue')
                else:
                    # Get the average time per visit.
                    empty_cue_time = empty_cue_time['sum'] / empty_cue_time['count']
                    print(f'Removing estimated sample time: {empty_cue_time}')
                    # Subtract off this amount from all entries.
                    for tracker in path_metrics.values():
                        tracker.Apply_Offset(-empty_cue_time)

                # Specify the period over which samples were gathered.
                #print(f"Metrics gathered over {state_data['path_metrics_timespan']} seconds")
                for tracker in path_metrics.values():
                    tracker.Set_Timespan(state_data['path_metrics_timespan'])

                for tracker in path_metrics.values():
                    tracker.Print(20)

                # TODO: maybe accumulate metrics across multiple calls.
                
                # Write results to a file.
                # TODO: collect data together from the trackers and state,
                # and regulate how often it dumps (to avoid excessive
                # writes during quick iterative testing).
                Write_Report(ai_counters, path_metrics, report_file_name)


            else:
                print(f'Error: {pipe_name} unrecognized command: {command} in message {message}')

        except Exception as ex:
            if test_python_client:
                raise ex
            print(ex)
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
      - Dict, keyed by entry name, holding the entry count.
    '''
    def __init__(self, type = ''):
        self.type = type
        self.counts = {}

    def Clear(self):
        self.counts.clear()

    def Set(self, name, count):
        self.counts[name] = float(count)

    def Apply_Offset(self, offset):
        # Adjust all entries directly.
        for key in self.counts:
            self.counts[key] += offset

    def Print(self, top = 5):
        '''
        Prints the top 5 (or however many) most frequent counts.
        Does nothing if no counts known.
        '''
        if not self.counts:
            return

        total_counts = sum(self.counts.values())
        msg = self.type + 's: {}\n'.format(total_counts)
        msg += self.type + ' counts (top {})\n'.format(top)

        lines = []
        remaining = top
        for name, count in sorted(self.counts.items(), key = lambda x: x[1], reverse = True):
            # Give spacing so the printout aligns somewhat.
            lines.append('{:<55}:{:6.0f} ({:.2f}%)'.format(
                name, 
                count,
                count / total_counts * 100))
            remaining -= 1
            if not remaining:
                break
            
        for line in lines:
            msg += '  '+line+'\n'
        print(msg)
        return


class Path_Metrics:
    '''
    Storage specifically for path metrics.
    TODO: track time interval of first to last metric sample, add
    compute for time per second and time per frame.
    
    * metrics
      - Dict, keyed by entry name, holding the metrics sent over.
      - Expected metrics: min, max, sum, count.
    * timespan
      - Float, period over which samples were gathered, in seconds.
      - May mismatch with the undelying metrics units (eg. 100 ns).
    '''
    def __init__(self, type = ''):
        self.type = type
        self.metrics = {}
        self.timespan = 0

    def Clear(self):
        self.metrics.clear()

    def Set(self, name, metrics_str):
        '''
        Takes a comma separated string with expected metric ordering:
        sum, min, max, count (ints), comma separated.
        Overwrites any possible prior metrics.
        TODO: support for summing with prior metrics.
        '''
        sum, min, max, count = metrics_str.split(',')
        self.metrics[name] = {
            'sum'   : int(sum), 
            'min'   : int(min), 
            'max'   : int(max), 
            'count' : int(count),
            }

    def Apply_Offset(self, offset):
        '''
        Apply a universal offset to the metrics.  min/max modified by offset,
        sum modified 'count' times of the offset. Affects all entries.
        No entry allowed to go below 0.
        '''
        for key in self.metrics:
            entry = self.metrics[key]
            entry['min'] = max(0, entry['min'] + offset)
            entry['max'] = max(0, entry['max'] + offset)
            entry['sum'] = max(0, entry['sum'] + offset * entry['count'])

    def Set_Timespan(self, timespan):
        '''
        Set the timespan over which samples were collected.
        As a float, in seconds.
        '''
        self.timespan = timespan

    # -Removed; expecting to do a higher level unified json dump instead.
    #def Dump(self):
    #    '''
    #    Dump metrics to a json file, using the current 'type' name,
    #    in this file's directory.
    #    '''
    #    with open(this_dir / f"{self.type.replace(' ','_')}.json", 'w') as file:
    #        json.dump(self.metrics, indent = 2)

    def Print(self, top = 5):
        '''
        Prints the top 5 (or however many) highest metrics, by sum.
        Does nothing if no metrics known.
        '''
        if not self.metrics:
            return

        # Compute total sum across all, in 100ns.
        total_sum_100ns = sum(x['sum'] for x in self.metrics.values())
        # Convert to seconds.
        total_sum_s = total_sum_100ns / 10000000

        # Line with how many paths were recoreded.
        msg = '\n'
        msg += self.type + 's: {} entries\n'.format(len(self.metrics))
        # Timespan of the gathering, and how much contribution all
        # entries make to this (discounting offet adjustment).
        msg += ' Timespan: {:.2f} seconds; contribution of entries: {:.2f} ({:.2f}%)\n'.format(
            self.timespan,
            total_sum_s,
            total_sum_s / self.timespan * 100,
            )
        msg += ' Top {}:\n'.format(top)
        

        lines = []
        remaining = top
        # Sort by sum, high to low.
        for name, metrics in sorted(self.metrics.items(), key = lambda x: x[1]['sum'], reverse = True):
            # Give spacing so the printout aligns somewhat.
            # (These tend to be floats due to the offset adjustment.)
            lines.append('{:<80}:{:6.0f} ({:.2f}%) ({:.1f} to {:.1f}, {} visits)'.format(
                name, 
                metrics['sum'],
                # Percent of all sums.
                (metrics['sum'] / total_sum_100ns * 100) if total_sum_100ns else 0,
                metrics['min'],
                metrics['max'],
                metrics['count'],
                ))
            remaining -= 1
            if not remaining:
                break
            
        for line in lines:
            msg += '  '+line+'\n'
        print(msg)
        return


def Write_Report(
        ai_counters, 
        path_metrics, 
        report_file_name
    ):
    '''
    Do some analysis of results, and write the profile to a file.
    '''
    # TODO



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
