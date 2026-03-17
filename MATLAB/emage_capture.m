%% emage_capture.m
% Automated emage capture loop – MATLAB port of connectToServer() in Main.java.
%
% Replicates the WebSocket-based automation state machine:
%
%   TempestSDR  ──[ws://server:8081/2]──  relay server  ──[/1]──  DUT browser
%
% State machine (mirrors Java lines 258-281):
%   ready == 1  → send ["1","next"]  → ready = 0
%   receive filename → set takeEmage = 1
%   after CAPTURE_DELAY_S  → save frame  → counter++  → ready = 1
%
% Usage:
%   emage_capture('ws://127.0.0.1:8081', 'out/', @get_current_frame)
%
% Arguments:
%   server_url        : WebSocket relay base URL  (e.g. 'ws://127.0.0.1:8081')
%   out_dir           : output folder for PNG files
%   get_frame_fn      : function handle () → [H×W] grey image (current SDR frame)
%   max_emages        : max frames to capture (default 400, matches Java)
%   capture_delay_s   : seconds to wait after "next" before capturing (default 3)
%
% Requires the MATLAB WebSocket support via the Java WebSocketClient library
% bundled with TempestSDR (java-websocket jar on the MATLAB Java class path),
% or any WebSocket adapter that exposes send/receive to MATLAB.
%
% NOTE: MATLAB does not ship a native WebSocket client.  This file provides
% the logic layer; the ws_* stubs below show what the adapter must implement.

function emage_capture(server_url, out_dir, get_frame_fn, max_emages, capture_delay_s)

if nargin < 4, max_emages      = 400; end
if nargin < 5, capture_delay_s = 3;   end

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

%% ── Connect to relay server as userID = 2 (Java: ws://…/2) ─────────────────
ws_url = [server_url '/2'];
fprintf('[emage_capture] Connecting to %s\n', ws_url);
ws = ws_connect(ws_url);       % adapter call – see ws_connect below

%% ── State variables (mirrors Main.java:171-174) ──────────────────────────────
ready          = 1;    % 1 = ready for next image
take_emage     = 0;    % 1 = capture triggered
emage_filename = '';   % received from webpage
counter        = 0;    % total emages captured

fprintf('[emage_capture] Starting capture loop (max %d)\n', max_emages);

while counter < max_emages

    %% ── Poll for incoming messages ───────────────────────────────────────
    msg = ws_poll(ws);          % non-blocking; returns '' if no message

    if ~isempty(msg)
        % Expected format: JSON array ["fromUserID", "payload"]
        parsed = jsondecode(msg);
        payload = parsed{2};

        % webpage sends back the filename it just displayed
        emage_filename = payload;
        take_emage     = 1;
        fprintf('[emage_capture] Received filename: %s\n', emage_filename);
    end

    %% ── Ready: request next image from webpage ───────────────────────────
    if ready == 1
        ready = 0;
        send_msg = jsonencode({"1", "next"});   % ["1","next"]
        ws_send(ws, send_msg);
        fprintf('[emage_capture] Sent "next" (counter=%d)\n', counter);
    end

    %% ── Capture: save current SDR frame after delay ──────────────────────
    if take_emage == 1
        pause(capture_delay_s);   % wait for phone to display image

        % Get current reconstructed frame from SDR
        frame = get_frame_fn();   % [H × W] normalised greyscale

        % Build output filename: <name><index>.png  (mirrors Java:266)
        fname = fullfile(out_dir, [emage_filename, '1.png']);
        imwrite(frame, fname);
        counter = counter + 1;
        fprintf('[emage_capture] Saved %s  (%d/%d)\n', fname, counter, max_emages);

        take_emage = 0;
        ready      = 1;
    end

    pause(0.05);   % yield so MATLAB event loop can receive messages
end

ws_close(ws);
fprintf('[emage_capture] Done. %d emages saved to %s\n', counter, out_dir);
end


%% ════════════════════════════════════════════════════════════════════════════
%  WebSocket adapter stubs
%  Replace these with your actual WebSocket implementation.
%  Options:
%    (a) Use MATLAB's built-in Java interface with the java-websocket JAR
%        already on TempestSDR's classpath.
%    (b) Use a third-party MATLAB WebSocket toolbox.
%    (c) Use a Python bridge (pyrunfile + websockets library).
%% ════════════════════════════════════════════════════════════════════════════

function ws = ws_connect(url)
% WS_CONNECT  Open a WebSocket connection.
%
% Minimal Java adapter using the same org.java_websocket library as Main.java:
%
%   javaaddpath('/path/to/java-websocket-1.x.x.jar');
%   uri = java.net.URI(url);
%   ws  = org.java_websocket.client.WebSocketClient(uri);
%   ws.connectBlocking();
%
% For now, return a placeholder struct.

warning('ws_connect: Replace this stub with a real WebSocket implementation.');
ws = struct('url', url, 'msgs', {{}});
end


function ws_send(ws, msg)
% WS_SEND  Send a text message over the WebSocket.
%   ws.send(msg);   % Java API
fprintf('[ws_send] → %s\n', msg);
end


function msg = ws_poll(ws)
% WS_POLL  Non-blocking receive; returns '' if no message is pending.
%   Implement as a drain of the message queue populated by onMessage callback.
msg = '';
end


function ws_close(ws)
% WS_CLOSE  Close the WebSocket connection.
%   ws.close();
fprintf('[ws_close] Connection closed.\n');
end
