/*
    0MQ wrapper in the D Programming Language
    by Christopher Nicholson-Sauls (2012).
*/

/***************************************************************************************************
 *
 */
module dzmq.zmq;

import  std.array   ,
        std.range   ,
        std.string  ;
import  zmq.zmq     ;


/***************************************************************************************************
 *
 */
struct ZMQVersion { static:
    enum    Major   = ZMQ_VERSION_MAJOR ,
            Minor   = ZMQ_VERSION_MINOR ,
            Patch   = ZMQ_VERSION_PATCH ;

    enum    String  = xformat( "%d.%d.%d", Major, Minor, Patch );
}


/***************************************************************************************************
 *
 */
class ZMQException : Exception {


    int code;


    /*******************************************************************************************
     *
     */
    this ( int a_code, string msg, string file = null, size_t line = 0 ) {
        code = a_code;
        super( msg, file, line );
    }

    ///ditto
    this ( string msg, string file = null, size_t line = 0 ) {
        this( zmq_errno(), msg, file, line );
    }


} // end ZMQException


/***************************************************************************************************
 *
 */
final class ZMQContext {


    /*******************************************************************************************
     *
     */
    this ( int a_ioThreads = ZMQ_IO_THREADS_DFLT ) {
        handle = zmq_ctx_new();
        if ( handle is null ) {
            throw new ZMQException( "Failed to create context" );
        }
        ioThreads = a_ioThreads;
    }
    
    unittest {
        auto ctx = new ZMQContext;
        assert( ctx !is null );
        assert( ctx.ioThreads == ZMQ_IO_THREADS_DFLT );
    }


    /*******************************************************************************************
     *
     */
    ~this () {
        if ( handle is null ) {
            return;
        }
        auto rc = zmq_ctx_destroy( handle );
        if ( rc != 0 ) {
            throw new ZMQException( "Failed to destroy context" );
        }
    }


    /*******************************************************************************************
     *
     */
    @property
    int ioThreads () {
        return zmq_ctx_get( handle, ZMQ_IO_THREADS );
    }
    
    ///ditto
    @property
    int ioThreads ( int val )
    
    in {
        assert( val > 0, "It is useless to have zero (or negative!?) io threads" );
    }
    
    body {
        return zmq_ctx_set( handle, ZMQ_IO_THREADS, val );
    }


    /*******************************************************************************************
     *
     */
    @property
    int maxSockets () {
        return zmq_ctx_get( handle, ZMQ_MAX_SOCKETS );
    }
    
    ///ditto
    @property
    int maxSockets ( int val )
    
    in {
        assert( val > 0, "It is useless to have a context with zero (or negative!?) max sockets" );
    }
    
    body {
        return zmq_ctx_set( handle, ZMQ_MAX_SOCKETS, val );
    }


    /*******************************************************************************************
     *
     */
    ZMQPoller poller ( int size = ZMQPoller.DEFAULT_SIZE ) {
        return new ZMQPoller( this, size );
    }


    /*******************************************************************************************
     *
     */
    ZMQSocket socket ( ZMQSocket.Type type )
    
    out ( result ) {
        assert( result !is null );
    }
    
    body {
        auto sock = new ZMQSocket( handle, type );
        sockets ~= sock;
        return sock;
    }


    /*******************************************************************************************
     *
     */
    ZMQSocket opDispatch ( string Sym ) ()
    
    if ( Sym.length > 6 && Sym[ $ - 6 .. $ ] == "Socket" )
    
    body {
        return socket( mixin( `ZMQSocket.Type.` ~ Sym[ 0 .. $ - 6 ].capitalize() ) );
    }


    ////////////////////////////////////////////////////////////////////////////////////////////
    private:
    ////////////////////////////////////////////////////////////////////////////////////////////


    ZMQSocket[] sockets ;
    void*       handle  ;


} // end ZMQContext


/***************************************************************************************************
 *
 */
final class ZMQSocket {


    /*******************************************************************************************
     *
     */
    static enum Type {
        Pair    = ZMQ_PAIR,
        Pub     ,
        Sub     ,
        Req     ,
        Rep     ,
        Dealer  ,
        Router  ,
        Pull    ,
        Push    ,
        XPub    ,
        XSub    ,

        Publisher   = Pub   ,
        Subscriber  = Sub   ,
        Requester   = Req   ,
        Replier     = Rep
    }


    /*******************************************************************************************
     *
     */
    private this ( void* contextHandle, Type a_type ) {
        handle = zmq_socket( contextHandle, a_type );
        if ( handle is null ) {
            throw new ZMQException( "Failed to create socket" );
        }
    }


    /*******************************************************************************************
     *
     */
    ~this () {
        if ( handle !is null ) {
            auto rc = zmq_close( handle );
            if ( rc != 0 ) {
                throw new ZMQException( "Failed to close socket" );
            }
        }
    }


    /*******************************************************************************************
     *
     */
    void bind ( string addr ) {
        auto rc = zmq_bind( handle, toStringz( addr ) );
        if ( rc != 0 ) {
            throw new ZMQException( "Failed to bind socket to " ~ addr );
        }
    }


    /*******************************************************************************************
     *
     */
    void connect ( string addr ) {
        auto rc = zmq_connect( handle, toStringz( addr ) );
        if ( rc != 0 ) {
            throw new ZMQException( "Failed to connect socket to " ~ addr );
        }
    }


    /*******************************************************************************************
     *
     */
    T receive ( T ) ( int flags = 0 ) {
        return cast( T ) _receive( flags );
    }


    /*******************************************************************************************
     *
     */
    void send ( R ) ( R input, int flags = 0 )
    
    if ( isInputRange!R )
    
    body {
        static if ( isForwardRange!R ) {
            input = input.save;
        }
        _send( cast( void[] ) input.array(), flags );
    }


    ////////////////////////////////////////////////////////////////////////////////////////////
    private:
    ////////////////////////////////////////////////////////////////////////////////////////////


    void* handle;


    /*******************************************************************************************
     *
     */
    void[] _receive ( int flags = 0 ) {
        zmq_msg_t msg;
        auto rc = zmq_msg_init( &msg );
        if ( rc != 0 ) {
            throw new ZMQException( "" );
        }
        
        rc = zmq_recvmsg( handle, &msg, flags );
        auto err = zmq_errno();
        if ( rc < 0 ) {
            if ( err != EAGAIN ) {
                zmq_msg_close( &msg );
                throw new ZMQException( "" );
            }
            rc = zmq_msg_close( &msg );
            if ( rc != 0 ) {
                throw new ZMQException( "" );
            }
            return null;
        }
       
        auto data = zmq_msg_data( &msg )[ 0 .. zmq_msg_size( &msg ) ].dup;
        rc = zmq_msg_close( &msg );
        assert( rc == 0 );
        
        return data;
    }

    
    /*******************************************************************************************
     *
     */
    void _send ( void[] data, int flags = 0 ) {
        auto rc = zmq_send( handle, data.ptr, data.length, flags );
        if ( rc < 0 ) {
            throw new ZMQException( "Failed to send" );
        }
    }


} // end ZMQSocket


/***************************************************************************************************
 *
 */
final class ZMQPoller {


    /*******************************************************************************************
     *
     */
    enum DEFAULT_SIZE = 32;


    /*******************************************************************************************
     *
     */
    private this ( ZMQContext a_context, int a_size = DEFAULT_SIZE ) {
        context = a_context;
        size    = a_size;
    }


    ////////////////////////////////////////////////////////////////////////////////////////////
    private:
    ////////////////////////////////////////////////////////////////////////////////////////////


    ZMQContext  context ;
    int         size    ;


} // end ZMQPoller
