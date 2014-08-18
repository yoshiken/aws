------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2012-2014, AdaCore                     --
--                                                                          --
--  This library is free software;  you can redistribute it and/or modify   --
--  it under terms of the  GNU General Public License  as published by the  --
--  Free Software  Foundation;  either version 3,  or (at your  option) any --
--  later version. This library is distributed in the hope that it will be  --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                    --
--                                                                          --
--  As a special exception under Section 7 of GPL version 3, you are        --
--  granted additional permissions described in the GCC Runtime Library     --
--  Exception, version 3.1, as published by the Free Software Foundation.   --
--                                                                          --
--  You should have received a copy of the GNU General Public License and   --
--  a copy of the GCC Runtime Library Exception along with this program;    --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see   --
--  <http://www.gnu.org/licenses/>.                                         --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

pragma Ada_2012;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Ordered_Maps;
with Ada.Unchecked_Deallocation;

with AWS.Config;
with AWS.Net.Generic_Sets;
with AWS.Net.Std;
with AWS.Translator;
with AWS.Utils;

package body AWS.Net.WebSocket.Registry is

   use GNAT;

   --  Containers for all registered constructors

   package Constructors is
     new Containers.Indefinite_Ordered_Maps (String, Factory);
   Factories : Constructors.Map;

   --  A queue for WebSocket with pending messages to be read

   package WebSocket_Queue is new Utils.Mailbox_G (Object_Class);
   type Queue_Ref is access WebSocket_Queue.Mailbox;

   --  A list of all WebSockets in the registry, this list is used to send or
   --  broadcast messages.

   procedure Unchecked_Free is
     new Ada.Unchecked_Deallocation (Object'Class, Object_Class);

   function Same_WS (Left, Right : Object_Class) return Boolean is
     (Left.Id = Right.Id);
   --  Equality is based on the unique id

   procedure WebSocket_Exception
     (WebSocket : not null access Object'Class;
      Message   : String;
      Error     : Error_Type);
   --  Call when an exception is caught. In this case we want to send the
   --  error message, the close message and shutdown the socket.

   package WebSocket_Set is
     new Containers.Ordered_Maps (UID, Object_Class, "=" => Same_WS);

   --  The socket set with all sockets to wait for data

   package FD_Set is new Net.Generic_Sets (Object_Class);
   use type FD_Set.Socket_Count;

   task type Watcher with Priority => Config.WebSocket_Priority is
   end Watcher;

   type Watcher_Ref is access all Watcher;
   --  This task is in charge of watching the WebSocket for incoming messages.
   --  It then places the WebSocket into a job queue to be processed by the
   --  reader tasks.

   task type Message_Reader with Priority => Config.WebSocket_Priority is
   end Message_Reader;
   --  Wait for WebSocket message to be ready, read them and call the Received
   --  callback. The a message has been read, the WebSocket is added back into
   --  the list of watched sockets.

   type Message_Reader_Set is array (Positive range <>) of Message_Reader;
   type Message_Reader_Set_Ref is access all Message_Reader_Set;

   --  Task objects

   Message_Queue   : Queue_Ref;

   Message_Watcher : Watcher_Ref;

   Message_Readers : Message_Reader_Set_Ref;

   Shutdown_Signal : Boolean := False;

   --  Concurrent access to Set above

   protected DB is

      procedure Initialize;
      --  Initialize the socket set by inserting a signaling socket

      procedure Finalize;
      --  Close signaling socket

      function Create_Set return FD_Set.Socket_Set_Type;
      --  Returns the set of watched WebSockets

      procedure Watch (WebSocket : Object_Class) with
        Pre => WebSocket /= null;
      --  Add a new Websocket into the set, release the current FD_Set.Wait
      --  call if any to ensure this new WebSocket will be watched too.

      procedure Remove (WebSocket : not null access Object'Class);
      --  Remove WebSocket at the given index

      entry Not_Empty;
      --  Returns if the Set is not empty

      procedure Send
        (To          : Recipient;
         Message     : Unbounded_String;
         Except_Peer : String;
         Timeout     : Duration := Forever);
      --  Send the given message to all matching WebSockets

      procedure Send
        (Socket    : in out Object'Class;
         Message   : String;
         Is_Binary : Boolean := False;
         Timeout   : Duration := Forever);

      procedure Send
        (Socket    : in out Object'Class;
         Message   : Unbounded_String;
         Is_Binary : Boolean := False;
         Timeout   : Duration := Forever);
      --  Same as above but can be used for large messages. The message is
      --  possibly sent fragmented.

      procedure Send
        (Socket    : in out Object'Class;
         Message   : Stream_Element_Array;
         Is_Binary : Boolean := True;
         Timeout   : Duration := Forever);

      procedure Close
        (To          : Recipient;
         Message     : String;
         Except_Peer : String;
         Timeout     : Duration := Forever;
         Error       : Error_Type := Normal_Closure);
      --  Close all matching Webockets

      procedure Close
        (Socket  : in out Object'Class;
         Message : String;
         Timeout : Duration := Forever;
         Error   : Error_Type := Normal_Closure);

      procedure Register (WebSocket : Object_Class) with
        Pre => WebSocket /= null;
      --  Register a new WebSocket

      procedure Unregister (WebSocket : not null access Object'Class);
      --  Unregister a WebSocket

      function Is_Registered (Id : UID) return Boolean;
      --  Returns True if the WebSocket Id is registered and False otherwise

      procedure Signal_Socket;
      --  Send a signal to the wait call

      procedure Receive
        (WebSocket : not null access Object'Class;
         Data      : out Stream_Element_Array;
         Last      : out Stream_Element_Offset);
      --  Get data from WebSocket

   private
      Sig1, Sig2 : Net.Std.Socket_Type; -- Signaling sockets
      Signal     : Boolean := False;    -- Transient signal, release Not_Emtpy
      Count      : Natural := 0;        -- Not counting signaling socket
      Registered : WebSocket_Set.Map;   -- Contains all the WebSocket ref

      Watched    : WebSocket_Set.Map;
      --  All WebSockets are registered into this set to check for incoming
      --  messages. When a message is ready the WebSocket is placed into the
      --  Message_Queue for being handled. When the message has been read
      --  and handled the WebSocket is put back into this set.
   end DB;

   -------------
   -- Watcher --
   -------------

   task body Watcher is
      Count : FD_Set.Socket_Count;
      WS    : Object_Class;
   begin
      loop
         DB.Not_Empty;
         exit when Shutdown_Signal;

         declare
            Set : FD_Set.Socket_Set_Type := DB.Create_Set;
            --  Note that the very first one is a signaling socket used to
            --  release the wait call. This first entry is not a WebSocket and
            --  should be ignored in most code below.
         begin
            --  Wait indefinitely, this call will be released either by an
            --  incoming message in a WebSocket or because the signaling socket
            --  has been used due to a new WebSocket registered. In this later
            --  case no message will be read, but on the next iteration the new
            --  WebSockets will be watched.

            FD_Set.Wait (Set, Duration'Last, Count);

            --  Queue all WebSocket having some data to read, skip the
            --  signaling socket.

            declare
               --  Skip first entry as it is not a websocket
               K : FD_Set.Socket_Count := 2;
            begin
               while K <= FD_Set.Count (Set) loop
                  if FD_Set.Is_Read_Ready (Set, K) then
                     WS := FD_Set.Get_Data (Set, K);
                     DB.Remove (WS);
                     Message_Queue.Add (WS);
                  end if;
                  K := K + 1;
               end loop;
            end;

         exception
            when E : others =>
               --  Send a On_Error message to all registered clients

               for K in 2 .. FD_Set.Count (Set) loop
                  WS := FD_Set.Get_Data (Set, K);
                  WS.State.Errno := Error_Code (Internal_Server_Error);
                  WS.On_Error
                    ("WebSocket Watcher server error, "
                     & Exception_Message (E));
               end loop;
         end;
      end loop;
   end Watcher;

   --------------------
   -- Message_Reader --
   --------------------

   task body Message_Reader is
      WebSocket : Object_Class;
      Data      : Stream_Element_Array (1 .. 4_096);
      Last      : Stream_Element_Offset;
      Message   : Unbounded_String;
   begin
      Handle_Message : loop
         begin
            Message := Null_Unbounded_String;

            Message_Queue.Get (WebSocket);

            --  A WebSocket is null when termination is requested

            exit Handle_Message when WebSocket = null;

            --  A message can be sent in multiple chunks and/or multiple
            --  frames with possibly some control frames in between text or
            --  binary ones. This loop handles those cases.

            Read_Message : loop
               begin
                  DB.Receive (WebSocket, Data, Last);
               exception
                  when E : Socket_Error =>
                     DB.Unregister (WebSocket);
                     WebSocket_Exception
                       (WebSocket,
                        Exception_Message (E),
                        Abnormal_Closure);
                     exit Read_Message;
               end;

               case WebSocket.Kind is
                  when Text | Binary =>
                     Append
                       (Message,
                        Translator.To_String (Data (Data'First .. Last)));

                     if WebSocket.End_Of_Message then

                        --  Validate the message as being valid UTF-8 string

                        if WebSocket.Kind = Text
                          and then not Utils.Is_Valid_UTF8 (Message)
                        then
                           DB.Unregister (WebSocket);
                           WebSocket.Shutdown;

                        else
                           WebSocket.On_Message (Message);
                           DB.Watch (WebSocket);
                        end if;

                        exit Read_Message;
                     end if;

                  when Connection_Close =>
                     DB.Unregister (WebSocket);
                     WebSocket.On_Close (To_String (Message));
                     WebSocket.Shutdown;
                     Unchecked_Free (WebSocket);
                     exit Read_Message;

                  when Ping | Pong =>
                     if WebSocket.End_Of_Message then
                        DB.Watch (WebSocket);
                        exit Read_Message;
                     end if;

                  when Connection_Open =>
                     --  Note that the On_Open message has been handled at the
                     --  time the WebSocket was registered.
                     exit Read_Message;

                  when Unknown =>
                     DB.Unregister (WebSocket);
                     WebSocket.On_Error ("Unknown frame type");
                     WebSocket.On_Close ("Unknown frame type");
                     WebSocket.Shutdown;
                     Unchecked_Free (WebSocket);
                     exit Read_Message;

               end case;
            end loop Read_Message;

         exception
            when E : others =>
               DB.Unregister (WebSocket);
               WebSocket_Exception
                 (WebSocket, Exception_Message (E), Protocol_Error);
         end;
      end loop Handle_Message;
   end Message_Reader;

   --------
   -- DB --
   --------

   protected body DB is

      ----------
      -- Close --
      ----------

      procedure Close
        (To          : Recipient;
         Message     : String;
         Except_Peer : String;
         Timeout     : Duration := Forever;
         Error       : Error_Type := Normal_Closure)
      is

         procedure Close_To (Position : WebSocket_Set.Cursor);

         -------------
         -- Close_To --
         -------------

         procedure Close_To (Position : WebSocket_Set.Cursor) is
            WebSocket : constant not null access Object'Class :=
                          WebSocket_Set.Element (Position);
         begin
            if (Except_Peer = "" or else WebSocket.Peer_Addr /= Except_Peer)
              and then
                (not To.URI_Set
                 or else GNAT.Regexp.Match (WebSocket.URI, To.URI))
              and then
                (not To.Origin_Set
                 or else GNAT.Regexp.Match (WebSocket.Origin, To.Origin))
            then
               DB.Unregister (WebSocket);
               WebSocket.State.Errno := Error_Code (Error);

               --  If an error occurs, we don't want to fail, shutdown the
               --  socket silently.

               begin
                  WebSocket.Set_Timeout (Timeout);
                  WebSocket.Close (Message, Error);
                  WebSocket.On_Close (Message);
               exception
                  when others =>
                     null;
               end;

               WebSocket.Shutdown;
            end if;
         end Close_To;

         Registered_Before : constant WebSocket_Set.Map := Registered;

      begin
         case To.Kind is
            when K_UID =>
               if Registered.Contains (To.WS_Id) then
                  declare
                     WebSocket : constant not null access Object'Class :=
                                   Registered (To.WS_Id);
                  begin
                     WebSocket.Set_Timeout (Timeout);
                     WebSocket.Close (Message, Error);
                     WebSocket.On_Close (Message);
                  exception
                     when others =>
                        null;
                  end;

               else
                  --  This WebSocket is not registered anymore

                  raise Socket_Error
                    with "WebSocket " & Utils.Image (Natural (To.WS_Id))
                         & " is not registered";
               end if;

            when K_URI =>
               Registered_Before.Iterate (Close_To'Access);
         end case;
      end Close;

      procedure Close
        (Socket  : in out Object'Class;
         Message : String;
         Timeout : Duration := Forever;
         Error   : Error_Type := Normal_Closure) is
      begin
         --  Look for WebSocket into the registered set, unregisted it is
         --  present.

         if Registered.Contains (Socket.Id) then
            Unregister (Registered (Socket.Id));
         end if;

         Socket.State.Errno := Error_Code (Error);
         Socket.Set_Timeout (Timeout);
         Socket.Close (Message, Error);
         Socket.On_Close (Message);
         Socket.Shutdown;
      end Close;

      ----------------
      -- Create_Set --
      ----------------

      function Create_Set return FD_Set.Socket_Set_Type is
      begin
         return Result : FD_Set.Socket_Set_Type do
            --  Add the signaling socket

            FD_Set.Add (Result, Sig1, null, FD_Set.Input);

            --  Add watched sockets

            for WS of Watched loop
               FD_Set.Add (Result, WS.all, WS, FD_Set.Input);
            end loop;
         end return;
      end Create_Set;

      --------------
      -- Finalize --
      --------------

      procedure Finalize is

         procedure On_Close (Position : WebSocket_Set.Cursor);

         --------------
         -- On_Close --
         --------------

         procedure On_Close (Position : WebSocket_Set.Cursor) is
            WebSocket : Object_Class :=
                          WebSocket_Set.Element (Position);
         begin
            WebSocket.State.Errno := Error_Code (Going_Away);

            --  We do not want to block if the peer is not responding, just
            --  allow 10 seconds for the close message to be accepted.
            --  In any case, we do not want to raise an exception. If an
            --  error occurs just close the socket silently.

            begin
               WebSocket.Set_Timeout (10.0);
               WebSocket.On_Close ("AWS server going down");
            exception
               when others =>
                  null;
            end;

            WebSocket.Shutdown;
            Unchecked_Free (WebSocket);
         end On_Close;

      begin
         Net.Std.Shutdown (Sig1);
         Net.Std.Shutdown (Sig2);

         --  Finally send a On_Close message to all registered WebSocket

         Registered.Iterate (On_Close'Access);
         Registered.Clear;
      end Finalize;

      ----------------
      -- Initialize --
      ----------------

      procedure Initialize is
      begin
         --  Create a signaling socket that will be used to exit from the
         --  infinite wait when a new WebSocket arrives.
         Net.Std.Socket_Pair (Sig1, Sig2);
      end Initialize;

      -------------------
      -- Is_Registered --
      -------------------

      function Is_Registered (Id : UID) return Boolean is
      begin
         return Registered.Contains (Id);
      end Is_Registered;

      ---------------
      -- Not_Empty --
      ---------------

      entry Not_Empty when Count > 0 or else Signal is
      begin
         --  It was a signal, consume the one by sent

         if Signal then
            Signal := False;

            declare
               Data : Stream_Element_Array (1 .. 1);
               Last : Stream_Element_Offset;
            begin
               AWS.Net.Std.Receive (Sig1, Data, Last);
            end;
         end if;
      end Not_Empty;

      -------------
      -- Receive --
      -------------

      procedure Receive
        (WebSocket : not null access Object'Class;
         Data      : out Stream_Element_Array;
         Last      : out Stream_Element_Offset) is
      begin
         WebSocket.Receive (Data, Last);
      end Receive;

      --------------
      -- Register --
      --------------

      procedure Register (WebSocket : Object_Class) is
      begin
         Registered.Insert (WebSocket.Id, WebSocket);
      end Register;

      ------------
      -- Remove --
      ------------

      procedure Remove (WebSocket : not null access Object'Class) is
      begin
         if Watched.Contains (WebSocket.Id) then
            Watched.Exclude (WebSocket.Id);
            Count := Count - 1;
         end if;
      end Remove;

      ----------
      -- Send --
      ----------

      procedure Send
        (To          : Recipient;
         Message     : Unbounded_String;
         Except_Peer : String;
         Timeout     : Duration := Forever)
      is

         procedure Send_To (Position : WebSocket_Set.Cursor);

         -------------
         -- Send_To --
         -------------

         procedure Send_To (Position : WebSocket_Set.Cursor) is
            WebSocket : constant not null access Object'Class :=
                          WebSocket_Set.Element (Position);
         begin
            if (Except_Peer = "" or else WebSocket.Peer_Addr /= Except_Peer)
              and then
                (not To.URI_Set
                 or else GNAT.Regexp.Match (WebSocket.URI, To.URI))
              and then
                (not To.Origin_Set
                 or else GNAT.Regexp.Match (WebSocket.Origin, To.Origin))
            then
               begin
                  WebSocket.Set_Timeout (Timeout);
                  WebSocket.Send (Message);
               exception
                  when E : others =>
                     Unregister (WebSocket);
                     WebSocket_Exception
                       (WebSocket, Exception_Message (E), Protocol_Error);
               end;
            end if;
         end Send_To;

         Registered_Before : constant WebSocket_Set.Map := Registered;

      begin
         case To.Kind is
            when K_UID =>
               if Registered.Contains (To.WS_Id) then
                  declare
                     WebSocket : constant not null access Object'Class :=
                                   Registered (To.WS_Id);
                  begin
                     WebSocket.Set_Timeout (Timeout);
                     WebSocket.Send (Message);
                  exception
                     when E : others =>
                        Unregister (WebSocket);
                        WebSocket_Exception
                          (WebSocket, Exception_Message (E), Protocol_Error);
                  end;

               else
                  --  This WebSocket is not registered anymore

                  raise Socket_Error
                    with "WebSocket " & Utils.Image (Natural (To.WS_Id))
                         & " is not registered";
               end if;

            when K_URI =>
               Registered_Before.Iterate (Send_To'Access);
         end case;
      end Send;

      procedure Send
        (Socket    : in out Object'Class;
         Message   : String;
         Is_Binary : Boolean := False;
         Timeout   : Duration := Forever) is
      begin
         Socket.Set_Timeout (Timeout);
         Socket.Send (Message, Is_Binary);
      end Send;

      procedure Send
        (Socket    : in out Object'Class;
         Message   : Unbounded_String;
         Is_Binary : Boolean := False;
         Timeout   : Duration := Forever) is
      begin
         Socket.Set_Timeout (Timeout);
         Socket.Send (Message, Is_Binary);
      end Send;

      procedure Send
        (Socket    : in out Object'Class;
         Message   : Stream_Element_Array;
         Is_Binary : Boolean := True;
         Timeout   : Duration := Forever) is
      begin
         Socket.Set_Timeout (Timeout);
         Socket.Send (Message, Is_Binary);
      end Send;

      -------------------
      -- Signal_Socket --
      -------------------

      procedure Signal_Socket is
      begin
         --  If a signal is pending no need to signal again the socket

         if not Signal then
            Net.Send (Sig2, Stream_Element_Array'(1 => 0));

            --  Also activate the signal to release Not_Empty for proper
            --  termination when there is no remaining socket.

            Signal := True;
         end if;
      end Signal_Socket;

      ----------------
      -- Unregister --
      ----------------

      procedure Unregister (WebSocket : not null access Object'Class) is
      begin
         Registered.Exclude (WebSocket.Id);

         Remove (WebSocket);
         Signal_Socket;
      end Unregister;

      -----------
      -- Watch --
      -----------

      procedure Watch (WebSocket : Object_Class) is
      begin
         if Is_Registered (WebSocket.Id)
           and then not Watched.Contains (WebSocket.Id)
         then
            Watched.Insert (WebSocket.Id, WebSocket);
            Count := Count + 1;
            Signal_Socket;
         end if;
      end Watch;

   end DB;

   -----------
   -- Close --
   -----------

   procedure Close
     (To          : Recipient;
      Message     : String;
      Except_Peer : String := "";
      Timeout     : Duration := Forever;
      Error       : Error_Type := Normal_Closure) is
   begin
      DB.Close (To, Message, Except_Peer, Timeout, Error);
   exception
      when others =>
         --  Should never fails even if the WebSocket is closed by peer
         null;
   end Close;

   procedure Close
     (Socket  : in out Object'Class;
      Message : String;
      Timeout : Duration := Forever;
      Error   : Error_Type := Normal_Closure) is
   begin
      DB.Close (Socket, Message, Timeout, Error);
   exception
      when others =>
         --  Should never fails even if the WebSocket is closed by peer
         null;
   end Close;

   -----------------
   -- Constructor --
   -----------------

   function Constructor (URI : String) return Registry.Factory is
      Position : constant Constructors.Cursor := Factories.Find (URI);
   begin
      if Constructors.Has_Element (Position) then
         return Constructors.Element (Position);
      else
         return Create'Access;
      end if;
   end Constructor;

   ------------
   -- Create --
   ------------

   function Create (URI : String; Origin : String := "") return Recipient is
      Result : Recipient (K_URI);
   begin
      if URI /= "" then
         Result.URI_Set := True;
         Result.URI     := GNAT.Regexp.Compile (URI);
      end if;

      if Origin /= "" then
         Result.Origin_Set := True;
         Result.Origin     := GNAT.Regexp.Compile (Origin);
      end if;

      return Result;
   end Create;

   function Create (Id : UID) return Recipient is
   begin
      return Result : Recipient (K_UID) do
         Result.WS_Id := Id;
      end return;
   end Create;

   -------------------
   -- Is_Registered --
   -------------------

   function Is_Registered (Id : UID) return Boolean is
   begin
      return DB.Is_Registered (Id);
   end Is_Registered;

   --------------
   -- Register --
   --------------

   procedure Register (URI : String; Factory : Registry.Factory) is
   begin
      Factories.Insert (URI, Factory);
   end Register;

   ----------
   -- Send --
   ----------

   procedure Send
     (To          : Recipient;
      Message     : Unbounded_String;
      Except_Peer : String := "";
      Timeout     : Duration := Forever) is
   begin
      DB.Send (To, Message, Except_Peer, Timeout);
   exception
      when others =>
         --  Should never fails even if the WebSocket is closed by peer
         null;
   end Send;

   procedure Send
     (To          : Recipient;
      Message     : String;
      Except_Peer : String := "";
      Timeout     : Duration := Forever) is
   begin
      Send (To, To_Unbounded_String (Message), Except_Peer, Timeout);
   end Send;

   procedure Send
     (To      : Recipient;
      Message : Unbounded_String;
      Request : AWS.Status.Data;
      Timeout : Duration := Forever) is
   begin
      Send
        (To, Message,
         Except_Peer => AWS.Status.Socket (Request).Peer_Addr,
         Timeout     => Timeout);
   end Send;

   procedure Send
     (To      : Recipient;
      Message : String;
      Request : AWS.Status.Data;
      Timeout : Duration := Forever) is
   begin
      Send
        (To, To_Unbounded_String (Message),
         Except_Peer => AWS.Status.Socket (Request).Peer_Addr,
         Timeout     => Timeout);
   end Send;

   procedure Send
     (Socket    : in out Object'Class;
      Message   : String;
      Is_Binary : Boolean := False;
      Timeout   : Duration := Forever) is
   begin
      DB.Send (Socket, Message, Is_Binary, Timeout);
   end Send;

   procedure Send
     (Socket    : in out Object'Class;
      Message   : Unbounded_String;
      Is_Binary : Boolean := False;
      Timeout   : Duration := Forever) is
   begin
      DB.Send (Socket, Message, Is_Binary, Timeout);
   end Send;

   procedure Send
     (Socket    : in out Object'Class;
      Message   : Stream_Element_Array;
      Is_Binary : Boolean := True;
      Timeout   : Duration := Forever) is
   begin
      DB.Send (Socket, Message, Is_Binary, Timeout);
   end Send;

   --------------
   -- Shutdown --
   --------------

   procedure Shutdown is
      procedure Unchecked_Free is new
        Unchecked_Deallocation (Watcher, Watcher_Ref);
      procedure Unchecked_Free is new
        Unchecked_Deallocation (Message_Reader_Set, Message_Reader_Set_Ref);
      procedure Unchecked_Free is new
        Unchecked_Deallocation (WebSocket_Queue.Mailbox, Queue_Ref);
   begin
      --  Check if a shutdown if not already in progress or if the servers have
      --  not been initialized.

      if Shutdown_Signal
        or else (Message_Watcher = null and then Message_Readers = null)
      then
         return;
      end if;

      --  First shutdown the watcher

      Shutdown_Signal := True;
      DB.Signal_Socket;

      --  Wait for proper termination to be able to free the task object

      while not Message_Watcher'Terminated loop
         delay 0.5;
      end loop;

      --  Now shutdown all the message readers

      for K in Message_Readers'Range loop
         Message_Queue.Add (null);
      end loop;

      for K in Message_Readers'Range loop
         while not Message_Readers (K)'Terminated loop
            delay 0.5;
         end loop;
      end loop;

      --  Now we can deallocate the task objects

      Unchecked_Free (Message_Readers);
      Unchecked_Free (Message_Watcher);
      Unchecked_Free (Message_Queue);

      DB.Finalize;
   end Shutdown;

   -----------
   -- Start --
   -----------

   procedure Start is
   begin
      DB.Initialize;
      Message_Queue :=
        new WebSocket_Queue.Mailbox (Config.WebSocket_Message_Queue_Size);
      Message_Watcher := new Watcher;
      Message_Readers :=
        new Message_Reader_Set (1 .. Config.Max_WebSocket_Handler);
   end Start;

   ----------------
   -- Watch_Data --
   ----------------

   procedure Watch_Data (WebSocket : Object'Class) is
      WS : Object_Class := new Object'Class'(WebSocket);
   begin
      --  Send a Connection_Open message

      WS.State.Kind := Connection_Open;
      WS.On_Open ("AWS WebSocket connection open");

      --  Register WebSocket

      DB.Register (WS);
      DB.Watch (WS);
   exception
      when others =>
         Unchecked_Free (WS);
         raise;
   end Watch_Data;

   -------------------------
   -- WebSocket_Exception --
   -------------------------

   procedure WebSocket_Exception
     (WebSocket : not null access Object'Class;
      Message   : String;
      Error     : Error_Type) is
   begin
      WebSocket.State.Errno := Error_Code (Error);
      WebSocket.On_Error (Message);

      if Error /= Abnormal_Closure then
         WebSocket.On_Close (Message);
      end if;

      WebSocket.Shutdown;
   exception
      when others =>
         --  Never propagate an exception at this point
         null;
   end WebSocket_Exception;

end AWS.Net.WebSocket.Registry;
