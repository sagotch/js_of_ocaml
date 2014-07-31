(* Js_of_ocaml compiler
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2014 Hugo Heuzard
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

(* Helper to compile js_of_ocaml toplevel
   with support for camlp4 syntax extensions *)

(* #use "topfind" *)
(* #require "findlib" *)

let verbose = ref false

let syntaxes = ref []
let syntaxes_mod = ref []
let add_syntax_pkg p =
  syntaxes:=!syntaxes @ [p]
let add_syntax_mod p =
  syntaxes_mod:=!syntaxes_mod @ [p]

let execute cmd =
  let s = String.concat " " cmd in
  if !verbose then Printf.printf "+ %s\n" s;
  let ret = Sys.command s in
  if ret <> 0
  then failwith (Printf.sprintf "Error: %s" s)

let to_clean = ref []
let clean file = to_clean := file :: !to_clean
let do_clean () =
  List.iter (fun x ->
      if Sys.file_exists x
      then Sys.remove x) !to_clean

module type CAMLP4 = sig   val build : string list -> string list -> string list end
module Camlp4 : CAMLP4 = struct

  (* We do the same as Camlp4Bin
     call Camlp4.Register.iter_and_take_callbacks
     after Every load of syntax module to initialize them.
     Camlp4 do it after dynlink;
     Since we statically link modules, we have to
     link dummy modules to trigger the callbacks *)
  let flush_str = Printf.sprintf
      "let _ = JsooTop.register_camlp4_syntax %S Camlp4.Register.iter_and_take_callbacks"

  let make_flush_module =
    let count = ref 0 in
    fun pkg_name ->
      incr count;
      let name = Printf.sprintf "camlp4_flush_%d" !count in
      let name_ml = name ^ ".ml" in
      let oc = open_out name_ml in
      clean name_ml;
      output_string oc (flush_str pkg_name);
      close_out oc;
      execute ["ocamlfind";"ocamlc";"-c";"-I";"+camlp4";"-package";"js_of_ocaml.toplevel";name_ml];
      clean (name ^ ".cmo");
      clean (name ^ ".cmi");
      (name^".cmo")

  let with_flush x archive =
    [ make_flush_module x ; archive]

  let resolve_syntaxes all =
    let preds = ["syntax";"preprocessor"] in
    let all = Findlib.package_deep_ancestors preds all in
    let ll = List.map (fun x ->
        try "-I" :: (Findlib.package_directory x) :: with_flush x (Findlib.package_property preds x "archive") with
        | Not_found -> []) all in
    List.flatten ll

  let build pkgs mods =
    if pkgs = [] && mods = [] then [] else
      let all = resolve_syntaxes pkgs @ mods in
      [
        "-I";"+camlp4";
        "dynlink.cma";
        "camlp4lib.cma";
	      "Camlp4Parsers/Camlp4OCamlRevisedParser.cmo";
	      "Camlp4Parsers/Camlp4OCamlParser.cmo";
      ]
      @ all
      @ ["Camlp4Top/Top.cmo"]
end

let usage () =
  Format.eprintf "Usage: jsoo_mktop [options] [ocamlfind arguments] @.";
  Format.eprintf " -verbose\t\toutput intermediate commands@.";
  Format.eprintf " -help\t\t\tDisplay usage@.";
  Format.eprintf " -top-syntax [pkg]\tInclude syntax extension provided by [pkg] findlib package@.";
  Format.eprintf " -top-syntax-mod [mod]\tInclude syntax extension provided by the module [mod]@.";
  exit 1

let rec scan_args acc = function
  | "-top-syntax" :: x :: xs -> add_syntax_pkg x; scan_args acc xs
  | "-top-syntax-mod" :: x :: xs -> add_syntax_mod x; scan_args acc xs
  | ("--verbose"|"-verbose")::xs -> verbose:=true; scan_args ("-verbose"::acc) xs
  | ("--help"|"-help"|"-h")::_ -> usage ()
  | x :: xs -> scan_args (x::acc) xs
  | [] -> List.rev acc

let _ =
  try
    let jsoo_top = ["-package";"js_of_ocaml.toplevel"] in
    let base_cmd = ["ocamlfind";"ocamlc";"-linkall";"-linkpkg"] in
    let args = List.tl (Array.to_list (Sys.argv)) in
    let args = scan_args [] args in
    let cmd = base_cmd @ Camlp4.build !syntaxes !syntaxes_mod  @ jsoo_top @ args in
    execute cmd;
    do_clean ()
  with exn -> do_clean (); raise exn
