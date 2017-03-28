module Ot = Pb_codegen_ocaml_type
module F = Pb_codegen_formatting 

let sp = Pb_codegen_util.sp

let unsupported json_label = 
  failwith (sp "Unsupported field type for field: %s" json_label) 

let setter_of_basic_type json_label basic_type pk = 
  match basic_type, pk with
  (* String *)
  | Ot.Bt_string, _ ->
    ("string", None) 

  (* Float *)
  | Ot.Bt_float, Ot.Pk_bits32 ->
    ("number", None)
  | Ot.Bt_float, Ot.Pk_bits64 -> 
    ("string", Some "string_of_float")

  (* Int32 *)
  | Ot.Bt_int32, Ot.Pk_varint _ 
  | Ot.Bt_int32, Ot.Pk_bits32 ->
    ("number", Some "Int32.to_float")
  
  (* Int64 *)
  | Ot.Bt_int64, Ot.Pk_varint _ 
  | Ot.Bt_int64, Ot.Pk_bits64 ->
    ("string", Some "Int64.to_string")
    (* 64 bit integer are always encoded as string since 
       only support up to 51 bits integer. An improvement
       could be to check for value > 2^51 and use int *)

  (* int *)
  | Ot.Bt_int, Ot.Pk_bits32 ->
    ("number", Some "float_of_int")

  | Ot.Bt_int, Ot.Pk_varint _ 
  | Ot.Bt_int, Ot.Pk_bits64 ->
    ("string", Some "string_of_int") 

  (* bool *)
  | Ot.Bt_bool, Ot.Pk_varint _ ->
    ("boolean", Some "Js_boolean.to_js_boolean")

  (* bytes *)
  | Ot.Bt_bytes, Ot.Pk_bytes -> unsupported json_label
  | _ -> unsupported json_label

let gen_field sc var_name json_label field_type pk = 

  match field_type, pk with
  | Ot.Ft_unit, _ -> 
    F.line sc "(* unit type -> encode nothing *)" 

  (* Basic types *)
  | Ot.Ft_basic_type basic_type, _ ->
    let setter, map_function = setter_of_basic_type json_label basic_type pk in
    begin match map_function with
    | None -> 
      F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.%s %s);" 
                   json_label setter var_name
    | Some map_function ->
      F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.%s (%s %s));"
        json_label setter map_function var_name 
    end
  
  (* User defined *)
  | Ot.Ft_user_defined_type udt, _ -> 
    let {Ot.udt_type; _} = udt in 
    let f_name = Pb_codegen_util.function_name_of_user_defined "encode" udt  in
    begin match udt_type with
    | `Message -> begin 
      F.line sc @@ sp "begin (* %s field *)" json_label;
      F.scope sc (fun sc -> 
        F.line sc "let json' = Js_dict.empty () in"; 
        F.line sc @@ sp "%s %s json';" f_name var_name;
        F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.object_ json');" 
          json_label;
      ); 
      F.line sc "end;"
    end
    | `Enum -> begin 
      F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.string (%s %s));"
        json_label f_name var_name
    end
    end

let gen_rft_nolabel sc rf_label (field_type, _, pk) = 
  let var_name = sp "v.%s" rf_label in 
  let json_label = Pb_codegen_util.camel_case_of_label rf_label in  
  gen_field sc var_name json_label field_type pk 

let gen_rft_optional_field sc rf_label (field_type, _, pk, _) = 
  F.line sc @@ sp "begin match v.%s with" rf_label; 
  F.scope sc (fun sc ->
    F.line sc "| None -> ()";
    F.line sc "| Some v ->";
    let json_label = Pb_codegen_util.camel_case_of_label rf_label in  
    gen_field sc "v" json_label field_type pk 
  ); 
  F.line sc "end;"

let gen_rft_repeated_field sc rf_label repeated_field = 
  let (repeated_type, field_type, _, pk, _) = repeated_field in
  begin match repeated_type with
  | Ot.Rt_list -> () 
  | Ot.Rt_repeated_field -> 
    (sp "Pbrt.Repeated_field is not supported with JSON (field: %s)" rf_label) 
    |> failwith    
  end; 

  let var_name = sp "v.%s" rf_label in 
  let json_label = Pb_codegen_util.camel_case_of_label rf_label in  

  match field_type, pk with
  | Ot.Ft_unit, _ -> 
    unsupported json_label

  | Ot.Ft_basic_type basic_type, _ ->
    let setter, map_function = setter_of_basic_type json_label basic_type pk in 
    begin match map_function with
    | None ->
      F.line sc @@ sp "let a = %s |> Array.of_list |> Array.map Js_json.%s in" 
        var_name setter;
    | Some map_function ->
      F.line sc @@ sp "let a = %s |> List.map %s |> Array.of_list |> Array.map Js_json.%s in" 
        var_name map_function setter;
    end;
    F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.array_ a);"
      json_label 
  
  (* User defined *)
  | Ot.Ft_user_defined_type udt, Ot.Pk_bytes -> 
    F.line sc @@ sp "let %s' = List.map (fun v ->" rf_label;
    F.scope sc (fun sc -> 
      F.line sc "let json' = Js_dict.empty () in"; 
      F.line sc @@ sp "%s v json';"
                   (Pb_codegen_util.function_name_of_user_defined "encode" udt);
      F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.object_ json');" 
        json_label;
      F.line sc "json' |> Array.of_list";
    ); 
    F.line sc @@ sp ") %s in" var_name;
    F.line sc @@ sp "Js_dict.set json \"%s\" (Js_json.array_ %s');"
      json_label rf_label

  | _ -> unsupported json_label
        
let gen_rft_variant_field sc rf_label {Ot.v_constructors; _} = 
  F.line sc @@ sp "begin match v.%s with" rf_label;
  F.scope sc (fun sc -> 
    List.iter (fun {Ot.vc_constructor; vc_field_type; vc_payload_kind; _} ->
      let var_name = "v" in 
      let json_label = 
        Pb_codegen_util.camel_case_of_constructor vc_constructor 
      in  
      F.line sc @@ sp "| %s v ->" vc_constructor; 
      F.scope sc (fun sc ->  
        match vc_field_type with
        | Ot.Vct_nullary -> 
          F.line sc @@ sp "Js_dict.set json \"%s\" Js_json.null" json_label
        | Ot.Vct_non_nullary_constructor field_type -> 
          gen_field sc var_name json_label field_type vc_payload_kind
      )
    ) v_constructors;
  ); 
  F.line sc @@ sp "end; (* match v.%s *)" rf_label

let gen_encode_record ?and_ {Ot.r_name; r_fields } sc = 
  let rn = r_name in 
  F.line sc @@ sp "%s encode_%s (v:%s) json = " 
      (Pb_codegen_util.let_decl_of_and and_) rn rn;
  F.scope sc (fun sc -> 
    List.iter (fun record_field -> 
      let {Ot.rf_label; rf_field_type; _ } = record_field in  

      match rf_field_type with 
      | Ot.Rft_nolabel nolabel_field  ->
        gen_rft_nolabel sc rf_label nolabel_field
     
      | Ot.Rft_repeated_field repeated_field  -> 
        gen_rft_repeated_field sc rf_label repeated_field  

      | Ot.Rft_variant_field variant_field -> 
        gen_rft_variant_field sc rf_label variant_field 
      
      | Ot.Rft_optional optional_field ->
        gen_rft_optional_field sc rf_label optional_field 

      | Ot.Rft_required _ ->
        Printf.eprintf "Only proto3 syntax supported in JSON encoding";
        exit 1

      | Ot.Rft_associative_field _ -> 
        Printf.eprintf "Map field are not currently supported for JSON";
        exit 1
        
    ) r_fields (* List.iter *); 
    F.line sc "()"
  )

let gen_encode_variant ?and_ {Ot.v_name; v_constructors} sc = 

  let process_v_constructor sc v_constructor = 
    let {
      Ot.vc_constructor; 
      Ot.vc_field_type; 
      Ot.vc_payload_kind; _} = v_constructor in 

    let json_label = Pb_codegen_util.camel_case_of_constructor vc_constructor in

    F.scope sc (fun sc -> 
      match vc_field_type with 
      | Ot.Vct_nullary -> 
        F.line sc @@ sp "| %s ->" vc_constructor; 
        F.line sc @@ sp "Js_dict.set json \"%s\" Js_json.null" json_label 

      | Ot.Vct_non_nullary_constructor field_type -> 
        F.line sc @@ sp "| %s v ->" vc_constructor; 
        gen_field sc "v" json_label field_type vc_payload_kind
    )
  in 

  F.line sc @@ sp "%s encode_%s (v:%s) json = " 
      (Pb_codegen_util.let_decl_of_and and_) v_name v_name;
  F.scope sc (fun sc -> 
    F.line sc "begin match v with";
    List.iter (process_v_constructor sc) v_constructors;
    F.line sc "end";
  ) 

let gen_encode_const_variant ?and_ {Ot.cv_name; Ot.cv_constructors} sc = 
  F.line sc @@ sp "%s encode_%s (v:%s) : string = " 
      (Pb_codegen_util.let_decl_of_and and_) cv_name cv_name; 
  F.scope sc (fun sc -> 
    F.line sc "match v with";
    List.iter (fun (constructor, _) -> 
      let json_value = String.uppercase constructor in 
      (* TODO it should not be upper case *)
      F.line sc @@ sp "| %s -> \"%s\"" constructor json_value
    ) cv_constructors
  ) 

let gen_struct ?and_ t sc  = 
  let (), has_encoded = 
    match t with 
    | {Ot.spec = Ot.Record r; _ } -> 
      gen_encode_record  ?and_ r sc, true
    | {Ot.spec = Ot.Variant v; _ } -> 
      gen_encode_variant ?and_ v sc, true 
    | {Ot.spec = Ot.Const_variant v; _ } ->
      gen_encode_const_variant ?and_ v sc, true
  in 
  has_encoded

let gen_sig ?and_ t sc = 
  let _ = and_ in
  let f type_name = 
    F.line sc @@ sp "val encode_%s : %s -> Js_json.t Js_dict.t -> unit" 
                 type_name type_name;
    F.line sc @@ sp ("(** [encode_%s v encoder] encodes [v] with the " ^^ 
                     "given [encoder] *)") type_name; 
  in 
  match t with 
  | {Ot.spec = Ot.Record {Ot.r_name; _ }; _}-> f r_name; true
  | {Ot.spec = Ot.Variant v; _ } -> f v.Ot.v_name; true 
  | {Ot.spec = Ot.Const_variant {Ot.cv_name; _ }; _ } -> 
    F.line sc @@ sp "val encode_%s : %s -> string"
      cv_name cv_name;
    F.line sc @@ sp ("(** [encode_%s v] returns JSON string*)") cv_name; 
    true

let ocamldoc_title = "Protobuf JSON Encoding"
