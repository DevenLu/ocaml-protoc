module Ot = Pb_codegen_ocaml_type 
module F = Pb_codegen_formatting

let sp = Pb_codegen_util.sp

let value_expression ~r_name ~rf_label field_type = 
  
  let basic_type helper_fun = 
    sp "Pbrt_bs.%s json \"%s\" \"%s\"" helper_fun r_name rf_label
  in

  match field_type with 
  | Ot.Ft_basic_type Ot.Bt_string -> basic_type "string"
  | Ot.Ft_basic_type Ot.Bt_float -> basic_type "float"
  | Ot.Ft_basic_type Ot.Bt_int -> basic_type "int" 
  | Ot.Ft_basic_type Ot.Bt_int32 -> basic_type "int32" 
  | Ot.Ft_basic_type Ot.Bt_int64 -> basic_type "int64" 
  | Ot.Ft_basic_type Ot.Bt_bool -> basic_type "bool" 
  | Ot.Ft_basic_type Ot.Bt_bytes -> basic_type "bytes" 
  | Ot.Ft_unit -> "()"
  | Ot.Ft_user_defined_type udt -> 
    let {Ot.udt_type; _} = udt in 
    let f_name = Pb_codegen_util.function_name_of_user_defined "decode" udt in 
    begin match udt_type with
    | `Message -> 
      let o = 
        sp "(Pbrt_bs.object_ json \"%s\" \"%s\")" r_name rf_label  
      in 
      "(" ^ f_name ^ " " ^ o ^ ")"
    | `Enum ->
      "(" ^ f_name ^ " json)"
    end

(* Generate the pattern match for a record field *)
let gen_rft_nolabel sc ~r_name ~rf_label (field_type, _, _) = 
   
  let json_label = Pb_codegen_util.camel_case_of_label rf_label in 
  let value_expression = value_expression ~r_name ~rf_label field_type in

  F.line sc @@ sp "| \"%s\" -> " json_label; 
  F.line sc @@ sp "  let json = Js_dict.unsafeGet json \"%s\" in" json_label;
  F.line sc @@ sp "  v.%s <- %s" rf_label value_expression

(* Generate all the pattern matches for a repeated field *)
let gen_rft_repeated_field sc ~r_name ~rf_label repeated_field =
  let (_, field_type, _, _, _) = repeated_field in

  let json_label = Pb_codegen_util.camel_case_of_label rf_label in 

  F.line sc @@ sp "| \"%s\" -> begin" json_label;

  F.scope sc (fun sc -> 
    F.line sc "let a = ";
    F.scope sc (fun sc -> 
      F.line sc @@ sp "let a = Js_dict.unsafeGet json \"%s\" in " json_label;
      F.line sc @@ sp "Pbrt_bs.array_ a \"%s\" \"%s\"" r_name rf_label; 
    ); 
    F.line sc "in";
    F.line sc @@ sp "v.%s <- Array.map (fun json -> " rf_label;

    let value_expression = value_expression ~r_name ~rf_label field_type in
    F.line sc @@ sp "  %s" value_expression;
    F.line sc ") a |> Array.to_list;";
  ); 

  F.line sc "end"

let gen_rft_optional_field sc ~r_name ~rf_label optional_field = 
  let (field_type, _, _, _) = optional_field in

  let json_label = Pb_codegen_util.camel_case_of_label rf_label in 
  let value_expression = value_expression ~r_name ~rf_label field_type in

  F.line sc @@ sp "| \"%s\" -> " json_label; 
  F.line sc @@ sp "  let json = Js_dict.unsafeGet json \"%s\" in" json_label;
  F.line sc @@ sp "  v.%s <- Some (%s)" rf_label value_expression

(* Generate pattern match for a variant field *)
let gen_rft_variant_field sc ~r_name ~rf_label {Ot.v_constructors; _} = 

  List.iter (fun {Ot.vc_constructor; vc_field_type; _} -> 

    let json_label = 
      Pb_codegen_util.camel_case_of_constructor vc_constructor 
    in

    match vc_field_type with
    | Ot.Vct_nullary -> begin 
      F.line sc @@ sp "| \"%s\" -> v.%s <- %s"
                   json_label rf_label vc_constructor
    end

    | Ot.Vct_non_nullary_constructor field_type ->
      let value_expression = 
        value_expression ~r_name ~rf_label field_type
      in

      F.line sc @@ sp "| \"%s\" -> " json_label;
      F.line sc @@ sp "  let json = Js_dict.unsafeGet json \"%s\" in" 
        json_label;
      F.line sc @@ sp "  v.%s <- %s (%s)" 
        rf_label vc_constructor value_expression;
    
  ) v_constructors

(* Generate decode function for a record *)
let gen_decode_record ?and_  {Ot.r_name; r_fields} sc = 
  let mutable_record_name = Pb_codegen_util.mutable_record_name r_name in 

  F.line sc @@ 
    sp "%s decode_%s json =" (Pb_codegen_util.let_decl_of_and and_) r_name; 

  F.scope sc (fun sc -> 
    F.line sc @@ sp "let v = default_%s () in" mutable_record_name;
    F.line sc @@ "let keys = Js_dict.keys json in"; 
    F.line sc @@ "let last_key_index = Array.length keys - 1 in"; 
    
    F.line sc "for i = 0 to last_key_index do";
    F.scope sc (fun sc -> 
      F.line sc "match Array.unsafe_get keys i with";
      
      (* Generate pattern match for all the possible message field *)
      List.iter (fun {Ot.rf_label; rf_field_type; _ } -> 

        match rf_field_type with
        | Ot.Rft_nolabel nolabel_field  ->
          gen_rft_nolabel sc ~r_name ~rf_label nolabel_field
        
        | Ot.Rft_optional optional_field -> 
          gen_rft_optional_field sc ~r_name ~rf_label optional_field

        | Ot.Rft_repeated_field repeated_field -> 
          gen_rft_repeated_field sc ~r_name ~rf_label repeated_field

        | Ot.Rft_variant_field variant_field -> 
          gen_rft_variant_field sc ~r_name ~rf_label variant_field

        | Ot.Rft_required _ ->
          Printf.eprintf "Only proto3 syntax supported in JSON encoding";
          exit 1

        | Ot.Rft_associative_field _ -> 
          Printf.eprintf "Map field are not currently supported for JSON";
          exit 1

      ) r_fields;
      
      (* Unknown fields are simply ignored *)
      F.empty_line sc; 
      F.line sc "| _ -> () (*Unknown fields are ignored*)";
    ); 
    F.line sc "done;"; 
    
    (* Transform the mutable record in an immutable one *)
    F.line sc "({"; 
    F.scope sc (fun sc -> 
      List.iter (fun {Ot.rf_label;_} -> 
        F.line sc @@ sp "%s = v.%s;" rf_label rf_label; 
      ) r_fields;
    ); 
    F.line sc @@ sp "} : %s)" r_name;
  )

(* Generate decode function for a variant type *)
let gen_decode_variant ?and_ {Ot.v_name; v_constructors} sc = 

  (* helper function for each constructor case *)
  let process_v_constructor sc {Ot.vc_constructor; vc_field_type; _} = 

    let json_label = Pb_codegen_util.camel_case_of_constructor vc_constructor in

    match vc_field_type with
    | Ot.Vct_nullary -> 
      F.line sc @@ sp "| \"%s\" -> %s"
                   json_label vc_constructor

    | Ot.Vct_non_nullary_constructor field_type ->
      let value_expression = 
        let r_name = v_name and rf_label = vc_constructor in 
        value_expression ~r_name ~rf_label field_type
      in

      F.line sc @@ sp "| \"%s\" -> " json_label ;
      F.line sc @@ sp "  let json = Js_dict.unsafeGet json \"%s\" in" 
        json_label;
      F.line sc @@ sp "  %s (%s)" vc_constructor value_expression;
  in

  F.line sc @@ 
    sp "%s decode_%s json =" (Pb_codegen_util.let_decl_of_and and_) v_name; 

  F.scope sc (fun sc -> 
    F.line sc @@ "let keys = Js_dict.keys json in"; 
    
    (* even though a variant should be an object with a single field, 
     * it is possible other fields are present in the JSON object. Therefore
     * we still need a loop to iterate over the key/value, even if in 99.99% 
     * of the cases it will be a single iteration *)
    F.line sc "let rec loop = function "; 
    F.scope sc (fun sc -> 
      F.line sc @@ sp "| -1 -> Pbrt_json.E.malformed_variant \"%s\"" 
        v_name;  
      F.line sc "| i -> ";
      F.scope sc (fun sc -> 
        F.line sc "begin match Array.unsafe_get keys i with";

        List.iter (process_v_constructor sc) v_constructors; 

        F.empty_line sc; 
        F.line sc "| _ -> loop (i - 1)";
        F.line sc "end";
      );
    );
    F.line sc "in"; 
    F.line sc "loop (Array.length keys - 1)";
  ) 

let gen_decode_const_variant ?and_ {Ot.cv_name; cv_constructors} sc = 
  F.line sc @@ sp "%s decode_%s (json:Js_json.t) =" 
    (Pb_codegen_util.let_decl_of_and and_) cv_name; 
  F.scope sc (fun sc -> 
    F.line sc @@ sp "match Pbrt_bs.string json \"%s\" \"value\" with" cv_name; 
    List.iter (fun (constructor, _) -> 
      F.line sc @@ sp "| \"%s\" -> %s"
        (String.uppercase constructor) constructor
    ) cv_constructors;  
    F.line sc @@ sp "| \"\" -> %s" 
      (fst @@ List.hd cv_constructors);
    F.line sc @@ sp "| _ -> Pbrt_json.E.malformed_variant \"%s\"" cv_name;  
  ) 

let gen_struct ?and_ t sc = 
  let (), has_encoded =  match t with 
    | {Ot.spec = Ot.Record r; _ }  -> 
      gen_decode_record ?and_ r sc, true
    | {Ot.spec = Ot.Variant v; _ } -> 
      gen_decode_variant ?and_ v sc, true
    | {Ot.spec = Ot.Const_variant v; _ } -> 
      gen_decode_const_variant ?and_ v sc, true
  in
  has_encoded

let gen_sig ?and_ t sc = 
  let _ = and_ in

  let f type_name = 
    F.line sc @@ sp "val decode_%s : Js_json.t Js_dict.t -> %s" 
                 type_name type_name ; 
    F.line sc @@ sp ("(** [decode_%s decoder] decodes a " ^^ 
                     "[%s] value from [decoder] *)") type_name type_name; 
  in 

  match t with 
  | {Ot.spec = Ot.Record {Ot.r_name; _ }; _} -> f r_name; true
  | {Ot.spec = Ot.Variant {Ot.v_name; _ }; _ } -> f v_name; true 
  | {Ot.spec = Ot.Const_variant {Ot.cv_name; _ }; _ } -> 
    F.line sc @@ sp "val decode_%s : Js_json.t -> %s" cv_name cv_name ; 
    F.line sc @@ sp "(** [decode_%s value] decodes a [%s] from a Json value*)"
      cv_name cv_name;
    true

let ocamldoc_title = "BS Decoding"
