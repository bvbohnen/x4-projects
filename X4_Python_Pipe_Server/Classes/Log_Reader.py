# Note: this is not currently used, but could prove useful at some point.

class Log_Reader:
    '''
    Class object for reading game output log files.
    This will advance to the end of the log when opened, and will increment
    through new log lines.

    Paramters:
    * log_path
      - Path, path to the log file to be read.

    Attributes:
    * file
      - Open instance of the file.
      - This will generally be advanced to near the end of the file.
    * partial_line
      - A partially read line for the current read attempt.
    '''
    '''
    Notes on possible approaches:
    1) named pipes
        Supported on windows and linux, but windows requires specific path
        names, so is not suitable for capturing game logs.
    2) writing inputmap from game
        The lua can save an inputmap file of a given name.
        Overall clumsier than logging files.
    3) Async polling the log file in append mode
        Game appends to the log, polling picks up new lines.
        This function will retain state to know which line was last read,
        to know when a new line arrives to be returned.

    Going to try (3) for now. This requires the log file be pre-opened.
    '''
    '''
    TODO: clean out the log occasionally of old lines.
    In quick test, x4 was happy appending to the file after lines were
    deleted.
    '''
    def __init__(self, log_path):
        self.file = open(log_path, 'r')
        self.partial_line = ''

        # In case there are existing contents already, do an initial advance
        # to the last line. TODO: maybe seek to the end.
        # Note: the log will always end with a newline after x4 finishes
        # updating it.
        while True:
            line = self.file.readline()
            if not line:
                break
        return

    def readline(self):
        '''
        Read a line from the log file.
        This will block until the line is ready, and so should only be
        used when the file is certain to be written in a timely manner.
        Waits for a newline; does not return on partial lines.

        TODO: timeout
        '''
        # Note: partial_line may have partial data from a prior read
        # attempt still in it, if there was a timeout. This call will
        # continue to append to that existing data.
        ret_line = None

        # Approach taken from example at:
        # https://stackoverflow.com/questions/12523044/how-can-i-tail-a-log-file-in-python/54263201#54263201
        # Basic idea: the file is read on the fly, but each read may only
        #  capture a partial line, depending on how the file is updated by
        #  the OS.
        # Readline will either return a full line, including newline, or will
        #  return a partial line at the end of the file.
        # So, each readline response will be appended to a running 'this_line'
        #  value, and only yields once newline is found.
        while True:
            # Try to read part of the file, up to a full line.
            chunk = self.file.readline()

            # If there was nothing new to read, this is an empty string.
            if not chunk:
                # Pause and try again.
                time.sleep(0.1)
                continue
        
            # Add the chunk to the running line.
            self.partial_line += chunk
            
            # If a newline was reached, the line is fully captured.
            if self.partial_line.endswith('\n'):
                # Return the line without the newline character.
                ret_line = self.partial_line[0:-1]
                # Reset the running line.
                self.partial_line = ''
                # Stop looping.
                break

        return ret_line

