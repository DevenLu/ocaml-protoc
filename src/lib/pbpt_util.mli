(** This module defines convenient function to create and manipulate
    the types define in the Ast module.
  *)

(** {2 Creators } *) 

val field : 
  ?options:Pbpt.field_options ->
  label:Pbpt.field_label-> 
  number:int -> 
  type_:string -> 
  string -> 
  Pbpt.field_label Pbpt.field

val oneof_field : 
  ?options:Pbpt.field_options ->
  number:int -> 
  type_:string -> 
  string -> 
  Pbpt.oneof_label Pbpt.field

val oneof :
  fields:Pbpt.oneof_label Pbpt.field list -> 
  string -> 
  Pbpt.oneof 

val message_body_field : 
  Pbpt.field_label Pbpt.field  -> 
  Pbpt.message_body_content  

val message_body_oneof_field  : 
  Pbpt.oneof -> 
  Pbpt.message_body_content 

val enum_value :
  int_value:int -> 
  string -> 
  Pbpt.enum_value 

val enum : 
  ?enum_values:Pbpt.enum_value list -> 
  string -> 
  Pbpt.enum 

val extension_range_single_number : int -> Pbpt.extension_range

val extension_range_range : int -> [ `Max | `Number of int ] -> Pbpt.extension_range 

val message_body_sub : 
  Pbpt.message -> 
  Pbpt.message_body_content

val message_body_enum: 
  Pbpt.enum -> 
  Pbpt.message_body_content

val message_body_extension: 
  Pbpt.extension_range list  -> 
  Pbpt.message_body_content

val message : 
  content:Pbpt.message_body_content list -> 
  string -> 
  Pbpt.message

val import : ?public:unit -> string -> Pbpt.import 

val proto: 
  ?file_option:Pbpt.file_option -> 
  ?package:string -> 
  ?import:Pbpt.import -> 
  ?message:Pbpt.message ->
  ?enum:Pbpt.enum ->
  ?proto:Pbpt.proto -> 
  unit -> 
  Pbpt.proto

(** {2 Miscellaneous functionality } *)

val message_printer :?level:int -> Pbpt.message -> unit 

