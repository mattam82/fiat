type idx_t = int
type data_t = Int64Word.t

let zero _ = 0
let succ (_, n) = Pervasives.succ n

type storage_t =
  { version: int;
    data: Cstruct.t;
    latest_version: int ref }

let of_cstruct (buf: Cstruct.t) : storage_t =
  { version = 0;
    data = buf;
    latest_version = ref 0 }

let to_cstruct (arr: storage_t) : Cstruct.t =
  arr.data

let destruct_idx _ _ _ =
  failwith "Not implemented: ArrayVector.destruct_idx"

let destruct_storage _ _ _ =
  failwith "Not implemented: ArrayVector.destruct_storage"

let throw_if_stale (fn: string) (arr: storage_t) =
  if arr.version <> !(arr.latest_version) then
    failwith (Printf.sprintf "ArrayVector: Array version mismatch in '%s': %d != %d."
                fn arr.version !(arr.latest_version))

let length (arr: storage_t) =
  Cstruct.len arr.data

let incr_version arr data =
  let version = Pervasives.succ !(arr.latest_version) in
  arr.latest_version := version;
  { version = version;
    latest_version = arr.latest_version;
    data = data }

let unsafe_getchar (buf: Cstruct.t) (idx: idx_t) =
  let open Cstruct in
  Bigarray.Array1.unsafe_get buf.buffer (buf.off + idx)

let unsafe_getdata (buf: Cstruct.t) (idx: idx_t) =
  Int64Word.of_char (unsafe_getchar buf idx)

let hd (_: int) (arr: storage_t) : Int64Word.t =
  throw_if_stale "hd" arr;
  unsafe_getdata arr.data 0

let sub arr off0 len =
  throw_if_stale "sub" arr;
  incr_version arr (Cstruct.sub arr.data off0 len)

let tl (_: int) (arr: storage_t) : storage_t =
  throw_if_stale "tl" arr;
  sub arr 1 (length arr - 1)

let index (_: int) (_: int) (x: data_t) (arr: storage_t) : idx_t option =
  throw_if_stale "index" arr;
  let rec loop x buf i =
    if i >= Cstruct.len buf then None
    else if unsafe_getchar buf i = x then Some i
    else loop x buf (i + 1)
  in loop (Int64Word.to_char x) arr.data 0

let nth _ (arr: storage_t) (idx: idx_t) : data_t =
  throw_if_stale "nth" arr;
  unsafe_getdata arr.data idx

let nth_opt _ (arr: storage_t) (idx: idx_t) : 'a option =
  throw_if_stale "nth_opt" arr;
  if idx < length arr then
    Some (unsafe_getdata arr.data idx)
  else None

let unsafe_setchar (buf: Cstruct.t) (idx: idx_t) (x: char) : unit =
  let open Cstruct in
  Bigarray.Array1.unsafe_set buf.buffer (buf.off + idx) x

let unsafe_setdata (buf: Cstruct.t) (idx: idx_t) (x: data_t) : unit =
  unsafe_setchar buf idx (Int64Word.to_char x)

let set_nth _ (arr: storage_t) (idx: idx_t) (x: 'a) : storage_t =
  throw_if_stale "set_nth" arr;
  unsafe_setdata arr.data idx x;
  incr_version arr arr.data

let fold_left_pair (f: 'a -> 'a -> 'b -> 'a) _ n (arr: storage_t) (init: 'b) (pad: 'a) =
  (* Printf.printf "Looping up to (min %d %d)\n%!" n (Array.length arr.data); *)
  let rec loop f arr acc pad len offset =
    if offset >= len then
      acc
    else if offset = len - 1  then
      f (unsafe_getdata arr.data offset) pad acc
    else
      let acc = f (unsafe_getdata arr.data offset)
                  (unsafe_getdata arr.data (offset + 1))
                  acc in
      loop f arr acc pad len (offset + 2)
  in loop f arr init pad (min n (length arr)) 0

let list_of_range _ (from: int) (len: int) (arr: storage_t) =
  throw_if_stale "list_of_range" arr;
  let rec loop from idx data acc =
    if idx < from then
      acc
    else
      loop from (idx - 1) data (unsafe_getdata data idx :: acc)
  in loop from (min (from + len) (length arr) - 1) arr.data []

let rec blit_list_unsafe (start: int) (list: data_t list) (data: Cstruct.t) =
  match list with
  | [] -> data
  | h :: t ->
     unsafe_setdata data start h;
     blit_list_unsafe (start + 1) t data

let blit_list _ start list arr =
  throw_if_stale "list_of_range" arr;
  let len = List.length list in
  if (start + len) <= length arr then
    let data' = blit_list_unsafe start list arr.data in
    Some (incr_version arr data', len)
  else None

let append _ _ (arr1: storage_t) (arr2: storage_t) : storage_t =
  throw_if_stale "append" arr1;
  throw_if_stale "append" arr2;
  of_cstruct (Cstruct.append arr1.data arr2.data)

let to_list _ (arr: storage_t) : data_t list =
  throw_if_stale "to_list" arr;
  let ls = ref [] in
  for idx = length arr - 1 downto 0 do
    ls := unsafe_getdata arr.data idx :: !ls
  done;
  !ls

let cons ((hd, _, tl): ('a * 'b * storage_t)) : storage_t =
  throw_if_stale "cons" tl;
  let hdbuf = Cstruct.create 1 in
  unsafe_setdata hdbuf 0 hd;
  of_cstruct (Cstruct.append hdbuf tl.data)

let empty () : storage_t =
  of_cstruct Cstruct.empty
