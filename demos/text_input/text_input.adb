------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2003                          --
--                                ACT-Europe                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  Example of text input through an HTTP server.

with Ada.Text_IO;

with AWS.Server;
with AWS.Log;
with AWS.Default;

with Text_Input_CB;

procedure Text_Input is

   WS : AWS.Server.HTTP;

begin
   Ada.Text_IO.Put_Line
     ("I'm on the port"
        & Positive'Image (AWS.Default.Server_Port) & ASCII.LF
        & "press Q key if you want me to stop.");

   AWS.Log.Start
     (Text_Input_CB.Text_Log,
      Split           => AWS.Log.Daily,
      Filename_Prefix => "text_input");

   AWS.Server.Start
     (WS, "Text input",
      Max_Connection => 4,
      Callback       => Text_Input_CB.Text_CB'Access);

   AWS.Server.Wait (AWS.Server.Q_Key_Pressed);

   AWS.Log.Stop (Text_Input_CB.Text_Log);
   AWS.Server.Shutdown (WS);
end Text_Input;