open Str
open Printf
open VarDRaftSerialized
open VarD
open Util

module type IntValue = sig
  val v : int
end

module type VardSerializedParams = sig
  val debug : bool
  val heartbeat_timeout : float
  val election_timeout : float
  val num_nodes : int
end

module DebugParams =
  functor (I : IntValue) ->
struct
  let debug = true
  let heartbeat_timeout = 2.0
  let election_timeout = 10.0
  let num_nodes = I.v
end

module BenchParams =
  functor (I : IntValue) ->
struct
  let debug = false
  let heartbeat_timeout = 0.05
  let election_timeout = 0.5
  let num_nodes = I.v
end

module VarDSerializedArrangement (P : VardSerializedParams) = struct
  type name = VarDRaftSerialized.name0
  type state = raft_data0
  type input = VarDRaftSerialized.raft_input
  type output = VarDRaftSerialized.raft_output
  type msg = Serializer_primitives.wire
  type res = (output list * state) * ((name * msg) list)
  type client_id = int
  let systemName = "VarDSerialized"
  let init = Obj.magic ((transformed_multi_params P.num_nodes).init_handlers)
  let reboot = Obj.magic (transformed_failure_params P.num_nodes)
  let handleIO (n : name) (inp : input) (st : state) = Obj.magic ((transformed_multi_params P.num_nodes).input_handlers (Obj.magic n) (Obj.magic inp) (Obj.magic st))
  let handleNet (n : name) (src: name) (m : msg) (st : state)  = Obj.magic ((transformed_multi_params P.num_nodes).net_handlers (Obj.magic n) (Obj.magic src) (Obj.magic m) (Obj.magic st))
  let handleTimeout (me : name) (st : state) =
    (Obj.magic (transformed_multi_params P.num_nodes).input_handlers (Obj.magic me) (Obj.magic Timeout) (Obj.magic st))
  let setTimeout _ s =
    match s.type0 with
    | Leader -> P.heartbeat_timeout
    | _ -> P.election_timeout +. (Random.float 0.1)
  let deserializeMsg = fun a -> a
  let serializeMsg = fun a -> a
  let deserializeInput = VarDSerializedSerialization.deserializeInput
  let serializeOutput = VarDSerializedSerialization.serializeOutput
  let debug = P.debug
  let debugRecv (s : state) (other, m) =
    (match Serializer_primitives.deserialize_top (msg_Serializer P.num_nodes) (msg_Serializer P.num_nodes).deserialize m with
    | Some (AppendEntries (t, leaderId, prevLogIndex, prevLogTerm, entries, commitIndex)) ->
      printf "[Term %d] Received %d entries from %d (currently have %d entries)\n"
        s.currentTerm (List.length entries) other (List.length s.log)
    | Some (AppendEntriesReply (_, entries, success)) ->
      printf "[Term %d] Received AppendEntriesReply %d entries %B, commitIndex %d\n"
        s.currentTerm (List.length entries) success s.commitIndex
    | Some (RequestVoteReply (t, votingFor)) ->
      printf "[Term %d] Received RequestVoteReply(%d, %B) from %d, have %d votes\n"
        s.currentTerm t votingFor other (List.length s.votesReceived)
    | Some _ -> ()
    | None -> printf "[Term %d] Received UNDESERIALIZABLE message from %d\n" s.currentTerm other);
    flush_all ()
  let debugSend s (other, m) =
    (match Serializer_primitives.deserialize_top (msg_Serializer P.num_nodes) (msg_Serializer P.num_nodes).deserialize m with
    | Some (AppendEntries (t, leaderId, prevLogIndex, prevLogTerm, entries, commitIndex)) ->
      printf "[Term %d] Sending %d entries to %d (currently have %d entries), commitIndex=%d\n"
        s.currentTerm (List.length entries) other (List.length s.log) commitIndex
    | Some (RequestVote _) ->
         printf "[Term %d] Sending RequestVote to %d, have %d votes\n"
           s.currentTerm other (List.length s.votesReceived)
    | Some _ -> ()
    | None -> printf "[Term %d] Sending UNDESERIALIZABLE message to %d\n" s.currentTerm other);
    flush_all ()
  let debugTimeout (s : state) = ()
  let debugInput s inp = ()
  let createClientId () =
    let upper_bound = 1073741823 in
    Random.int upper_bound
  let serializeClientId = string_of_int
end