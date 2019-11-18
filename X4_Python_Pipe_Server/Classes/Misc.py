
class Client_Garbage_Collected(Exception):
    '''
    Custom exception to signal upstream when a client pipe is being
    garbage collected. Added as an alternative to proper file closing,
    since that started crashing x4 around v3.0.
    '''
