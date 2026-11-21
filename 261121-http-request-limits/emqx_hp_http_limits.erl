%%--------------------------------------------------------------------
%% Loader for the 261121-http-request-limits hot patch.
%%
%% The patch replaces several modules that depend on each other. This
%% module loads them into a running node in one step, and then closes
%% the HTTP/2 connections that clients opened before the load, because
%% a connection keeps the settings it was opened with.
%%
%%   emqx eval 'c:l(emqx_hp_http_limits), emqx_hp_http_limits:status().'
%%   emqx eval 'c:l(emqx_hp_http_limits), emqx_hp_http_limits:apply().'
%%
%% It is not needed when the node is restarted with the files in its
%% patches directory. status/0 can still be used to verify that case.
%%--------------------------------------------------------------------
-module(emqx_hp_http_limits).

-export([status/0, apply/0, http2_connections/0, close_http2_connections/0]).

%% How long a connection may take to close before it is killed. With
%% cowboy 2.13 (EMQX 5.10 and later) a connection first lets the
%% requests in progress finish, for up to about 4 seconds with the
%% default listener options.
-define(CLOSE_TIMEOUT, 10000).

%% One entry per group of releases that ship identical modules:
%% {Files, [{Module, OriginalCodeMD5, PatchedCodeMD5}]}.
sets() ->
    [
        {"5.8", [
            {cow_hpack, "FFC1E633FD5B36EAEFC39096CB22F00A", "BF94EA2EDA2FDD5DCB793344C5B815F6"},
            {cow_http2_machine, "E1D3BCF29F2A589F435EEBE234FC34FA", "F43518B1AB78939F3DA527113843A128"},
            {cow_http_te, "43DF23E0AFB05EDA3D8AF0C2FA14C60C", "E2B69833FA940F2EBC2FD9C3F0653B72"},
            {cowboy_http, "459A4886D3061DABB09974F099BD5889", "56F250B8D2E5F3410E86AD9BFB92B009"},
            {cowboy_req, "C32C7E85EA40A1AA52FE467C27B1BC7D", "F013DC431E7D8136B188170C4D6717E6"}
        ]},
        {"5.9", [
            {cow_hpack, "7A6F76406B4143466A4E0428B476653B", "860978773A4A60A902E474E0C7CD4C2F"},
            {cow_http2_machine, "657A04E5A638C20404E52243025FDCD1", "19D081DD971931E491BEFA4508981513"},
            {cow_http_te, "47798FB0F55AF4D1C36631F18C9225D7", "795459D3E694FC3E97D92B82FDDC3B3D"},
            {cowboy_http, "BF3D2BCC58EC91037B8FD5C49459456A", "67B56E4F094F53CEA466B3957CB2F1AE"},
            {cowboy_req, "C643BCE21AD10B1D8071310FA688717C", "B3858D4651CF2114D4665E699E6F1336"}
        ]},
        {"5.10 or 6.0", [
            {cow_hpack, "05DE0706AC2045E586B699B7243F3D85", "EE296C4FC890CEF3BD279D90B3C6E6CD"},
            {cow_http2_machine, "EA9F9A7AAEB65689501CCEC14774D70B", "7517189C2CFD5E18838BF9DEB3AACEA4"},
            {cow_http_te, "47798FB0F55AF4D1C36631F18C9225D7", "795459D3E694FC3E97D92B82FDDC3B3D"},
            {cow_qpack, "7877DEEF8715974D0784E53981CC467E", "3513F6E18AAB7B0B67A4E05937124137"},
            {cowboy_http, "9F8D6087C651516C980C94319C91E0C0", "628067AD38915D88D5EE869E71C5245F"},
            {cowboy_req, "3AE7362736DF4AF60CFC149B05A134BE", "90FEF0A734311B41AD78FC3293932541"}
        ]},
        {"6.1, 6.2 or 6.3.0-6.3.2", [
            {cow_hpack, "DE8078B89A4C8C8BE7CD911C3FFC2711", "27BE23DA8462D8AF952087AA328FF61E"},
            {cow_http2_machine, "CD698E0A75DF63684A3F8D1DF4EFE92A", "50B875103C18A5502211B4D293C8A1E4"},
            {cow_http_te, "034B88792D949496AFFC34A055896C9A", "99B17CF79AADE364598B8E4DECC325D6"},
            {cow_qpack, "6AD743D87657BD0A64938EC3876A6D07", "615B370A90E997E74B3E51512177EFBC"},
            {cowboy_http, "5F602ED95EA6666972395B66A9EC0F2A", "DCA16239AC5C56EE50A9468A3CAFE515"},
            {cowboy_req, "48BB25D8B47120A0B5DFF6BE08A9E972", "2EFB1845C90B33EE442A61AF0883B6F1"}
        ]},
        {"6.3.3", [
            {cow_http, "D0D12DA738BACB1A04A97968B355A77E", "157760F88A7EAC74AAB4812DA3CA3235"},
            {cow_http2, "04F03D825A050DECB0887480A3265378", "2A08505685D94F6B9E4D87E066749727"},
            {cow_http2_machine, "2F1AC50D438AD53BED08E667B3FD801F", "B6F085C19109A28C89828B58295EB780"},
            {cow_http_hd, "15110C3F4FE0DCE3743C2527FFE4953D", "A068C214F3A2070DD37B03A306DEB7A1"},
            {cow_http_struct_hd, "71556D0E7FE3C0168E4B4659DC5C8ADC", "C3714241CB614065AC83ADE1EFD51050"},
            {cow_http_te, "EF766BB5374B63CFB13E1F0457494837", "1A00F01C0F7D8EF8F84FED733BCBCFAA"},
            {gun_http2, "CD2156840D6E2C19C5A84472C8C26995", "12ED1ED5C10AD1C9C1919A22B8F5EADD"},
            {cowboy_http, "5F602ED95EA6666972395B66A9EC0F2A", "511FEB01B7291C527E522591BEFD9FF7"},
            {cowboy_http2, "721190AAF27DB83ED8CEFCA5B00E6E6A", "520185B59489E547977D96FB574A1553"},
            {cowboy_req, "48BB25D8B47120A0B5DFF6BE08A9E972", "2EFB1845C90B33EE442A61AF0883B6F1"}
        ]}
    ].

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

%% Report which modules are patched, and whether the files next to this
%% module are the files for this node. Changes nothing.
-spec status() -> map().
status() ->
    Base = #{release => release(), otp_release => erlang:system_info(otp_release)},
    case select_set() of
        {ok, Files, Mods} ->
            Dir = dir(),
            States = [{M, state(M, O, P), file_state(Dir, M, P)} || {M, O, P} <- Mods],
            Base#{
                files => Files,
                patch => summary(States),
                modules => States,
                other_files => other_files(Dir, Mods),
                http2_connections => attempt(fun() -> length(http2_connections()) end)
            };
        none ->
            Base#{patch => unsupported, modules => loaded_md5s()}
    end.

%% Load the patched modules, then close the HTTP/2 connections that
%% clients opened before the load. Safe to run again.
-spec apply() -> {ok, already_applied} | {ok, map()} | {error, term()}.
apply() ->
    case select_set() of
        {ok, Files, Mods} ->
            ToLoad = [{M, P} || {M, O, P} <- Mods, state(M, O, P) =:= original],
            do_apply(Files, Mods, ToLoad);
        none ->
            {error, {unsupported, loaded_md5s()}}
    end.

%% Pids of the HTTP/2 connections that clients have open to this node.
-spec http2_connections() -> [pid()].
http2_connections() ->
    [Pid || Ref <- listeners(), Pid <- connections(Ref), is_http2(Pid)].

%% Close them. Clients reconnect. Returns how many were closed.
-spec close_http2_connections() -> non_neg_integer().
close_http2_connections() ->
    Pids = http2_connections(),
    Closers = [spawn_monitor(fun() -> close(Pid) end) || Pid <- Pids],
    lists:foreach(
        fun({Closer, MRef}) ->
            receive
                {'DOWN', MRef, process, Closer, _} -> ok
            end
        end,
        Closers
    ),
    length(Pids).

%%--------------------------------------------------------------------
%% Load
%%--------------------------------------------------------------------

do_apply(_Files, _Mods, []) ->
    {ok, already_applied};
do_apply(Files, Mods, ToLoad) ->
    Dir = dir(),
    case {read_files(Dir, ToLoad), other_files(Dir, Mods)} of
        {{ok, Prepared}, []} ->
            case [M || {M, _} <- ToLoad, not code:soft_purge(M)] of
                [] ->
                    load(Files, Prepared);
                InUse ->
                    {error, {old_code_in_use, InUse}}
            end;
        {{ok, _}, Other} ->
            {error, {files_of_another_release, Dir, Other}};
        {{error, Bad}, _} ->
            {error, {bad_files, Dir, Bad}}
    end.

load(Files, Prepared) ->
    case code:atomic_load(Prepared) of
        ok ->
            %% The modules are loaded now. If closing fails, say so in
            %% the result: close_http2_connections/0 can be run again.
            Closed = attempt(fun close_http2_connections/0),
            {ok, #{
                files => Files,
                loaded => [M || {M, _, _} <- Prepared],
                http2_connections_closed => Closed
            }};
        {error, Reason} ->
            {error, {load_failed, Reason}}
    end.

%% Every file must be present and must be the file of this patch.
read_files(Dir, ToLoad) ->
    Results = [read_file(Dir, M, P) || {M, P} <- ToLoad],
    case [Bad || {error, Bad} <- Results] of
        [] -> {ok, [Ok || {ok, Ok} <- Results]};
        Bad -> {error, Bad}
    end.

read_file(Dir, M, PatchedMD5) ->
    File = filename:join(Dir, atom_to_list(M) ++ ".beam"),
    case file:read_file(File) of
        {ok, Bin} ->
            case beam_md5(Bin) of
                PatchedMD5 -> {ok, {M, File, Bin}};
                Other -> {error, {M, {unexpected_md5, Other}}}
            end;
        {error, Reason} ->
            {error, {M, Reason}}
    end.

file_state(Dir, M, PatchedMD5) ->
    case read_file(Dir, M, PatchedMD5) of
        {ok, _} -> file_ok;
        {error, {M, enoent}} -> file_missing;
        {error, {M, _}} -> file_wrong
    end.

%% Files in the directory that belong to this patch, but to another
%% group of releases. They must not be there: a restart would load them.
other_files(Dir, Mods) ->
    Mine = [M || {M, _, _} <- Mods],
    All = lists:usort([M || {_, Ms} <- sets(), {M, _, _} <- Ms]),
    [M || M <- All -- Mine, filelib:is_regular(filename:join(Dir, atom_to_list(M) ++ ".beam"))].

beam_md5(Bin) ->
    case beam_lib:md5(Bin) of
        {ok, {_, MD5}} -> hex(MD5);
        _ -> not_a_beam_file
    end.

dir() ->
    filename:dirname(code:which(?MODULE)).

%%--------------------------------------------------------------------
%% Module state
%%--------------------------------------------------------------------

%% The set whose modules all are, on this node, the original or the
%% patched build. A node that runs anything else is not supported.
select_set() ->
    Matching = [
        {Files, Mods}
     || {Files, Mods} <- sets(),
        lists:all(fun({M, O, P}) -> state(M, O, P) =/= unknown end, Mods)
    ],
    case Matching of
        [{Files, Mods}] -> {ok, Files, Mods};
        _ -> none
    end.

state(M, Original, Patched) ->
    case loaded_md5(M) of
        Original -> original;
        Patched -> patched;
        _ -> unknown
    end.

loaded_md5(M) ->
    _ = code:ensure_loaded(M),
    try
        hex(M:module_info(md5))
    catch
        _:_ -> not_loaded
    end.

loaded_md5s() ->
    Mods = lists:usort([M || {_, Mods} <- sets(), {M, _, _} <- Mods]),
    [{M, loaded_md5(M)} || M <- Mods].

summary(States) ->
    case lists:usort([S || {_, S, _} <- States]) of
        [patched] -> applied;
        [original] -> not_applied;
        _ -> partly_applied
    end.

hex(Bin) ->
    binary_to_list(binary:encode_hex(Bin)).

attempt(Fun) ->
    try
        Fun()
    catch
        Class:Reason -> {failed, {Class, Reason}}
    end.

release() ->
    try
        emqx_release:version()
    catch
        _:_ -> unknown
    end.

%%--------------------------------------------------------------------
%% HTTP/2 connections
%%--------------------------------------------------------------------

%% Every HTTP listener of the node runs under ranch: the Dashboard and
%% REST API, MQTT over WebSocket, the gateways and the gRPC servers.
listeners() ->
    case ranch:info() of
        Info when is_map(Info) -> maps:keys(Info);
        Info when is_list(Info) -> [Ref || {Ref, _} <- Info]
    end.

%% A listener can stop between the two calls. It has no connections then.
connections(Ref) ->
    try
        ranch:procs(Ref, connections)
    catch
        _:_ -> []
    end.

is_http2(Pid) ->
    case erlang:process_info(Pid, current_stacktrace) of
        {current_stacktrace, Stack} -> lists:keymember(cowboy_http2, 1, Stack);
        undefined -> false
    end.

%% Ask the connection to stop: it sends GOAWAY and closes. Kill it if
%% it does not stop in time.
close(Pid) ->
    MRef = erlang:monitor(process, Pid),
    _ = (catch sys:terminate(Pid, shutdown, ?CLOSE_TIMEOUT)),
    receive
        {'DOWN', MRef, process, Pid, _} -> ok
    after ?CLOSE_TIMEOUT ->
        exit(Pid, kill),
        receive
            {'DOWN', MRef, process, Pid, _} -> ok
        end
    end.
