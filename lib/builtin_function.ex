defmodule BuiltinFunction do
  @moduledoc """
  Module responsible for determining ExLisp built-in functions
  and compiling them to Erlang Abstract Format.
  """

  @builtin_mappings %{
    # Arithmetic
    :+ => {:+, :add},
    :- => {:-, :sub},
    :* => {:*, :mul},
    :/ => {:/, :divide},
    :"1+" => {:"1+", :one_plus},
    :_cl_1plus_ => {:"1+", :one_plus},
    :"1-" => {:"1-", :one_minus},
    :_cl_1minus_ => {:"1-", :one_minus},
    :abs => {:abs, :abs},
    :min => {:min, :min},
    :max => {:max, :max},
    :mod => {:mod, :mod},
    :rem => {:rem, :rem},
    :floor => {:floor, :floor},
    :ceiling => {:ceiling, :ceiling},
    :round => {:round, :round},
    :truncate => {:truncate, :truncate},
    :sqrt => {:sqrt, :sqrt},
    :exp => {:exp, :exp},
    :expt => {:expt, :expt},
    :log => {:log, :log},
    :sin => {:sin, :sin},
    :cos => {:cos, :cos},
    :tan => {:tan, :tan},
    :asin => {:asin, :asin},
    :acos => {:acos, :acos},
    :atan => {:atan, :atan},
    :gcd => {:gcd, :gcd},
    :lcm => {:lcm, :lcm},
    :numerator => {:numerator, :numerator},
    :_cl_numerator_ => {:numerator, :numerator},
    :denominator => {:denominator, :denominator},
    :_cl_denominator_ => {:denominator, :denominator},
    :rational => {:rational, :rational},
    :_cl_rational_ => {:rational, :rational},
    :complex => {:complex, :complex},
    :_cl_complex_ => {:complex, :complex},
    :realpart => {:realpart, :realpart},
    :_cl_realpart_ => {:realpart, :realpart},
    :imagpart => {:imagpart, :imagpart},
    :_cl_imagpart_ => {:imagpart, :imagpart},

    # Numeric comparisons
    := => {:=, :num_eq},
    :"/=" => {:"/=", :num_neq},
    :_cl_neq_ => {:"/=", :num_neq},
    :< => {:<, :num_lt},
    :_cl_lt_ => {:<, :num_lt},
    :<= => {:<=, :num_lte},
    :_cl_lte_ => {:<=, :num_lte},
    :> => {:>, :num_gt},
    :_cl_gt_ => {:>, :num_gt},
    :>= => {:>=, :num_gte},
    :_cl_gte_ => {:>=, :num_gte},

    # Equality and predicates
    :eq => {:eq, :eq},
    :eqt => {:eq, :eq},
    :eql => {:eql, :eql},
    :eqlt => {:eql, :eql},
    :equal => {:equal, :equal},
    :equalt => {:equal, :equal},
    :equalp => {:equalp, :equalp},
    :atom => {:atom, :atom},
    :consp => {:consp, :consp},
    :listp => {:listp, :listp},
    :numberp => {:numberp, :numberp},
    :realp => {:realp, :realp},
    :_cl_realp_ => {:realp, :realp},
    :rationalp => {:rationalp, :rationalp},
    :_cl_rationalp_ => {:rationalp, :rationalp},
    :integerp => {:integerp, :integerp},
    :floatp => {:floatp, :floatp},
    :symbolp => {:symbolp, :symbolp},
    :keywordp => {:keywordp, :keywordp},
    :_cl_keywordp_ => {:keywordp, :keywordp},
    :stringp => {:stringp, :stringp},
    :characterp => {:characterp, :characterp},
    :functionp => {:functionp, :functionp},
    :complexp => {:complexp, :complexp},
    :_cl_complexp_ => {:complexp, :complexp},
    :typep => {:typep, :typep},
    :subtypep => {:subtypep, :subtypep},
    :_cl_subtypep_ => {:subtypep, :subtypep},
    :simple_string_p => {:simple_string_p, :simple_string_p},
    :_cl_simple_string_p_ => {:simple_string_p, :simple_string_p},
    :"simple-string-p" => {:simple_string_p, :simple_string_p},
    :null => {:null, :null},
    :endp => {:endp, :endp},
    :not => {:not, :not_fn},
    :zerop => {:zerop, :zerop},
    :plusp => {:plusp, :plusp},
    :minusp => {:minusp, :minusp},
    :evenp => {:evenp, :evenp},
    :oddp => {:oddp, :oddp},
    :boundp => {:boundp, :boundp},
    :fboundp => {:fboundp, :fboundp},

    # List operations
    :cons => {:cons, :cons},
    :rplaca => {:rplaca, :rplaca},
    :_cl_rplaca_ => {:rplaca, :rplaca},
    :rplacd => {:rplacd, :rplacd},
    :_cl_rplacd_ => {:rplacd, :rplacd},
    :car => {:car, :car},
    :cdr => {:cdr, :cdr},
    :first => {:first, :first},
    :rest => {:rest, :rest},
    :second => {:second, :second},
    :third => {:third, :third},
    :fourth => {:fourth, :fourth},
    :fifth => {:fifth, :fifth},
    :sixth => {:sixth, :sixth},
    :seventh => {:seventh, :seventh},
    :eighth => {:eighth, :eighth},
    :ninth => {:ninth, :ninth},
    :tenth => {:tenth, :tenth},
    :caar => {:caar, :caar},
    :cadr => {:cadr, :cadr},
    :cdar => {:cdar, :cdar},
    :cddr => {:cddr, :cddr},
    :caaar => {:caaar, :caaar},
    :caadr => {:caadr, :caadr},
    :cadar => {:cadar, :cadar},
    :caddr => {:caddr, :caddr},
    :cdaar => {:cdaar, :cdaar},
    :cdadr => {:cdadr, :cdadr},
    :cddar => {:cddar, :cddar},
    :cdddr => {:cdddr, :cdddr},
    :cadddr => {:cadddr, :cadddr},
    :caaaar => {:caaaar, :caaaar},
    :caaadr => {:caaadr, :caaadr},
    :caadar => {:caadar, :caadar},
    :caaddr => {:caaddr, :caaddr},
    :cadaar => {:cadaar, :cadaar},
    :cadadr => {:cadadr, :cadadr},
    :caddar => {:caddar, :caddar},
    :cdaaar => {:cdaaar, :cdaaar},
    :cdaadr => {:cdaadr, :cdaadr},
    :cdadar => {:cdadar, :cdadar},
    :cdaddr => {:cdaddr, :cdaddr},
    :cddaar => {:cddaar, :cddaar},
    :cddadr => {:cddadr, :cddadr},
    :cdddar => {:cdddar, :cdddar},
    :cddddr => {:cddddr, :cddddr},
    :list => {:list, :list},
    :"list*" => {:"list*", :list_star},
    :_cl_list_star_ => {:"list*", :list_star},
    :append => {:append, :append},
    :nconc => {:nconc, :nconc},
    :reverse => {:reverse, :reverse},
    :nreverse => {:nreverse, :nreverse},
    :length => {:length, :length},
    :elt => {:elt, :elt},
    :_cl_elt_ => {:elt, :elt},
    :nth => {:nth, :nth},
    :nthcdr => {:nthcdr, :nthcdr},
    :last => {:last, :last},
    :butlast => {:butlast, :butlast},
    :member => {:member, :member},
    :assoc => {:assoc, :assoc},
    :assoc_if => {:assoc_if, :assoc_if},
    :_cl_assoc_if_ => {:assoc_if, :assoc_if},
    :assoc_if_not => {:assoc_if_not, :assoc_if_not},
    :_cl_assoc_if_not_ => {:assoc_if_not, :assoc_if_not},
    :rassoc => {:rassoc, :rassoc},
    :rassoc_if => {:rassoc_if, :rassoc_if},
    :_cl_rassoc_if_ => {:rassoc_if, :rassoc_if},
    :rassoc_if_not => {:rassoc_if_not, :rassoc_if_not},
    :_cl_rassoc_if_not_ => {:rassoc_if_not, :rassoc_if_not},
    :member_if => {:member_if, :member_if},
    :_cl_member_if_ => {:member_if, :member_if},
    :member_if_not => {:member_if_not, :member_if_not},
    :_cl_member_if_not_ => {:member_if_not, :member_if_not},
    :acons => {:acons, :acons},
    :pairlis => {:pairlis, :pairlis},
    :_cl_pairlis_ => {:pairlis, :pairlis},
    :make_list => {:make_list, :make_list},
    :_cl_make_list_ => {:make_list, :make_list},
    :nbutlast => {:nbutlast, :nbutlast},
    :_cl_nbutlast_ => {:nbutlast, :nbutlast},
    :copy_list => {:copy_list, :copy_list},
    :_cl_copy_list_ => {:copy_list, :copy_list},
    :copy_alist => {:copy_alist, :copy_alist},
    :_cl_copy_alist_ => {:copy_alist, :copy_alist},
    :copy_tree => {:copy_tree, :copy_tree},
    :_cl_copy_tree_ => {:copy_tree, :copy_tree},
    :revappend => {:revappend, :revappend},
    :nreconc => {:nreconc, :nreconc},
    :tree_equal => {:tree_equal, :tree_equal},
    :_cl_tree_equal_ => {:tree_equal, :tree_equal},
    :tailp => {:tailp, :tailp},
    :ldiff => {:ldiff, :ldiff},
    :list_length => {:list_length, :list_length},
    :"list-length" => {:list_length, :list_length},
    :_cl_list_length_ => {:list_length, :list_length},
    :put_plist => {:put_plist, :put_plist},
    :_cl_put_plist_ => {:put_plist, :put_plist},
    :set_nth => {:set_nth, :set_nth},
    :_cl_set_nth_ => {:set_nth, :set_nth},
    :union => {:union, :union},
    :nunion => {:nunion, :nunion},
    :_cl_nunion_ => {:nunion, :nunion},
    :intersection => {:intersection, :intersection},
    :nintersection => {:nintersection, :nintersection},
    :_cl_nintersection_ => {:nintersection, :nintersection},
    :set_difference => {:set_difference, :set_difference},
    :_cl_set_difference_ => {:set_difference, :set_difference},
    :nset_difference => {:nset_difference, :nset_difference},
    :_cl_nset_difference_ => {:nset_difference, :nset_difference},
    :set_exclusive_or => {:set_exclusive_or, :set_exclusive_or},
    :_cl_set_exclusive_or_ => {:set_exclusive_or, :set_exclusive_or},
    :nset_exclusive_or => {:nset_exclusive_or, :nset_exclusive_or},
    :_cl_nset_exclusive_or_ => {:nset_exclusive_or, :nset_exclusive_or},
    :subsetp => {:subsetp, :subsetp},
    :mapcar => {:mapcar, :mapcar},
    :mapc => {:mapc, :mapc},
    :mapcan => {:mapcan, :mapcan},
    :maplist => {:maplist, :maplist},
    :mapl => {:mapl, :mapl},
    :mapcon => {:mapcon, :mapcon},
    :remove => {:remove, :remove},
    :remove_if => {:remove_if, :remove_if},
    :_cl_remove_if_ => {:remove_if, :remove_if},
    :remove_if_not => {:remove_if_not, :remove_if_not},
    :_cl_remove_if_not_ => {:remove_if_not, :remove_if_not},
    :delete => {:delete, :remove},
    :_cl_delete_ => {:delete, :remove},
    :delete_if => {:delete_if, :remove_if},
    :_cl_delete_if_ => {:delete_if, :remove_if},
    :delete_if_not => {:delete_if_not, :remove_if_not},
    :_cl_delete_if_not_ => {:delete_if_not, :remove_if_not},
    :remove_duplicates => {:remove_duplicates, :remove_duplicates},
    :_cl_remove_duplicates_ => {:remove_duplicates, :remove_duplicates},
    :delete_duplicates => {:delete_duplicates, :delete_duplicates},
    :_cl_delete_duplicates_ => {:delete_duplicates, :delete_duplicates},
    :substitute => {:substitute, :substitute},
    :_cl_substitute_ => {:substitute, :substitute},
    :substitute_if => {:substitute_if, :substitute_if},
    :_cl_substitute_if_ => {:substitute_if, :substitute_if},
    :substitute_if_not => {:substitute_if_not, :substitute_if_not},
    :_cl_substitute_if_not_ => {:substitute_if_not, :substitute_if_not},
    :nsubstitute => {:nsubstitute, :substitute},
    :_cl_nsubstitute_ => {:nsubstitute, :substitute},
    :nsubstitute_if => {:nsubstitute_if, :substitute_if},
    :_cl_nsubstitute_if_ => {:nsubstitute_if, :substitute_if},
    :nsubstitute_if_not => {:nsubstitute_if_not, :substitute_if_not},
    :_cl_nsubstitute_if_not_ => {:nsubstitute_if_not, :substitute_if_not},
    :concatenate => {:concatenate, :concatenate},
    :_cl_concatenate_ => {:concatenate, :concatenate},
    :search => {:search, :search},
    :_cl_search_ => {:search, :search},
    :map_into => {:map_into, :map_into},
    :_cl_map_into_ => {:map_into, :map_into},
    :mismatch => {:mismatch, :mismatch},
    :_cl_mismatch_ => {:mismatch, :mismatch},
    :replace => {:replace, :replace},
    :_cl_replace_ => {:replace, :replace},
    :fill => {:fill, :fill},
    :_cl_fill_ => {:fill, :fill},
    :copy_seq => {:copy_seq, :copy_seq},
    :_cl_copy_seq_ => {:copy_seq, :copy_seq},
    :subseq => {:subseq, :subseq},
    :_cl_subseq_ => {:subseq, :subseq},
    :make_sequence => {:make_sequence, :make_sequence},
    :_cl_make_sequence_ => {:make_sequence, :make_sequence},
    :merge => {:merge, :merge},
    :_cl_merge_ => {:merge, :merge},
    :map => {:map, :map},
    :_cl_map_ => {:map, :map},
    :count => {:count, :count},
    :_cl_count_ => {:count, :count},
    :count_if => {:count_if, :count_if},
    :_cl_count_if_ => {:count_if, :count_if},
    :count_if_not => {:count_if_not, :count_if_not},
    :_cl_count_if_not_ => {:count_if_not, :count_if_not},
    :find => {:find, :find},
    :_cl_find_ => {:find, :find},
    :find_if => {:find_if, :find_if},
    :_cl_find_if_ => {:find_if, :find_if},
    :find_if_not => {:find_if_not, :find_if_not},
    :_cl_find_if_not_ => {:find_if_not, :find_if_not},
    :position => {:position, :position},
    :_cl_position_ => {:position, :position},
    :position_if => {:position_if, :position_if},
    :_cl_position_if_ => {:position_if, :position_if},
    :position_if_not => {:position_if_not, :position_if_not},
    :_cl_position_if_not_ => {:position_if_not, :position_if_not},
    :every => {:every, :every},
    :_cl_every_ => {:every, :every},
    :some => {:some, :some},
    :_cl_some_ => {:some, :some},
    :notany => {:notany, :notany},
    :_cl_notany_ => {:notany, :notany},
    :notevery => {:notevery, :notevery},
    :_cl_notevery_ => {:notevery, :notevery},
    :reduce => {:reduce, :reduce},
    :_cl_reduce_ => {:reduce, :reduce},
    :sort => {:sort, :sort},
    :_cl_sort_ => {:sort, :sort},
    :stable_sort => {:stable_sort, :stable_sort},
    :_cl_stable_sort_ => {:stable_sort, :stable_sort},
    :subst => {:subst, :subst},
    :_cl_subst_ => {:subst, :subst},
    :nsubst => {:nsubst, :nsubst},
    :_cl_nsubst_ => {:nsubst, :nsubst},
    :subst_if => {:subst_if, :subst_if},
    :_cl_subst_if_ => {:subst_if, :subst_if},
    :nsubst_if => {:nsubst_if, :nsubst_if},
    :_cl_nsubst_if_ => {:nsubst_if, :nsubst_if},
    :subst_if_not => {:subst_if_not, :subst_if_not},
    :_cl_subst_if_not_ => {:subst_if_not, :subst_if_not},
    :nsubst_if_not => {:nsubst_if_not, :nsubst_if_not},
    :_cl_nsubst_if_not_ => {:nsubst_if_not, :nsubst_if_not},
    :sublis => {:sublis, :sublis},
    :_cl_sublis_ => {:sublis, :sublis},
    :nsublis => {:nsublis, :nsublis},
    :_cl_nsublis_ => {:nsublis, :nsublis},
    :adjoin => {:adjoin, :adjoin},
    :_cl_adjoin_ => {:adjoin, :adjoin},
    :get_properties => {:get_properties, :get_properties},
    :_cl_get_properties_ => {:get_properties, :get_properties},
    :rem_plist => {:rem_plist, :rem_plist},
    :_cl_rem_plist_ => {:rem_plist, :rem_plist},
    :array_has_fill_pointer_p => {:array_has_fill_pointer_p, :array_has_fill_pointer_p},
    :_cl_array_has_fill_pointer_p_ => {:array_has_fill_pointer_p, :array_has_fill_pointer_p},
    :adjustable_array_p => {:adjustable_array_p, :adjustable_array_p},
    :_cl_adjustable_array_p_ => {:adjustable_array_p, :adjustable_array_p},

    # Hash table
    :make_hash_table => {:make_hash_table, :make_hash_table},
    :_cl_make_hash_table_ => {:make_hash_table, :make_hash_table},
    :gethash => {:gethash, :gethash},
    :gethash_mv => {:gethash_mv, :gethash_mv},
    :_cl_gethash_mv_ => {:gethash_mv, :gethash_mv},
    :remhash => {:remhash, :remhash},
    :clrhash => {:clrhash, :clrhash},
    :hash_table_count => {:hash_table_count, :hash_table_count},
    :_cl_hash_table_count_ => {:hash_table_count, :hash_table_count},
    :hash_table_p => {:hash_table_p, :hash_table_p},
    :_cl_hash_table_p_ => {:hash_table_p, :hash_table_p},
    :maphash => {:maphash, :maphash},
    :sxhash => {:sxhash, :sxhash},
    :_cl_sxhash_ => {:sxhash, :sxhash},

    # Array / vector
    :make_array => {:make_array, :make_array},
    :_cl_make_array_ => {:make_array, :make_array},
    :fill_pointer => {:fill_pointer, :fill_pointer},
    :_cl_fill_pointer_ => {:fill_pointer, :fill_pointer},
    :vector => {:vector, :vector},
    :aref => {:aref, :aref},
    :_cl_aref_ => {:aref, :aref},
    :svref => {:svref, :svref},
    :_cl_svref_ => {:svref, :svref},
    :bit => {:bit, :aref},
    :_cl_bit_ => {:bit, :aref},
    :sbit => {:sbit, :aref},
    :_cl_sbit_ => {:sbit, :aref},
    :arrayp => {:arrayp, :arrayp},
    :vectorp => {:vectorp, :vectorp},
    :bit_vector_p => {:bit_vector_p, :bit_vector_p},
    :_cl_bit_vector_p_ => {:bit_vector_p, :bit_vector_p},
    :"bit-vector-p" => {:bit_vector_p, :bit_vector_p},
    :simple_bit_vector_p => {:simple_bit_vector_p, :simple_bit_vector_p},
    :_cl_simple_bit_vector_p_ => {:simple_bit_vector_p, :simple_bit_vector_p},
    :"simple-bit-vector-p" => {:simple_bit_vector_p, :simple_bit_vector_p},
    :simple_vector_p => {:simple_vector_p, :simple_vector_p},
    :_cl_simple_vector_p_ => {:simple_vector_p, :simple_vector_p},
    :"simple-vector-p" => {:simple_vector_p, :simple_vector_p},
    :array_element_type => {:array_element_type, :array_element_type},
    :_cl_array_element_type_ => {:array_element_type, :array_element_type},
    :"array-element-type" => {:array_element_type, :array_element_type},
    :array_rank => {:array_rank, :array_rank},
    :_cl_array_rank_ => {:array_rank, :array_rank},
    :"array-rank" => {:array_rank, :array_rank},
    :array_displacement => {:array_displacement, :array_displacement},
    :_cl_array_displacement_ => {:array_displacement, :array_displacement},
    :"array-displacement" => {:array_displacement, :array_displacement},
    :array_row_major_index => {:array_row_major_index, :array_row_major_index},
    :_cl_array_row_major_index_ => {:array_row_major_index, :array_row_major_index},
    :"array-row-major-index" => {:array_row_major_index, :array_row_major_index},
    :array_dimension => {:array_dimension, :array_dimension},
    :_cl_array_dimension_ => {:array_dimension, :array_dimension},
    :array_dimensions => {:array_dimensions, :array_dimensions},
    :_cl_array_dimensions_ => {:array_dimensions, :array_dimensions},
    :array_total_size => {:array_total_size, :array_total_size},
    :_cl_array_total_size_ => {:array_total_size, :array_total_size},
    :vector_push => {:vector_push, :vector_push},
    :_cl_vector_push_ => {:vector_push, :vector_push},
    :vector_push_extend => {:vector_push_extend, :vector_push_extend},
    :_cl_vector_push_extend_ => {:vector_push_extend, :vector_push_extend},
    :vector_pop => {:vector_pop, :vector_pop},
    :_cl_vector_pop_ => {:vector_pop, :vector_pop},
    :adjust_array => {:adjust_array, :adjust_array},
    :_cl_adjust_array_ => {:adjust_array, :adjust_array},
    :coerce => {:coerce, :coerce},
    :_cl_coerce_ => {:coerce, :coerce},

    # Structures / Objects (CLOS)
    :make_instance => {:make_instance, :make_instance},
    :_cl_make_instance_ => {:make_instance, :make_instance},
    :slot_value => {:slot_value, :slot_value},
    :_cl_slot_value_ => {:slot_value, :slot_value},
    :slot_boundp => {:slot_boundp, :slot_boundp},
    :_cl_slot_boundp_ => {:slot_boundp, :slot_boundp},
    :slot_makunbound => {:slot_makunbound, :slot_makunbound},
    :_cl_slot_makunbound_ => {:slot_makunbound, :slot_makunbound},

    # Strings / Characters
    :"string=" => {:"string=", :string_eq},
    :_cl_string_eq_ => {:"string=", :string_eq},
    :string_eq => {:"string=", :string_eq},
    :"string/=" => {:"string/=", :string_neq},
    :_cl_string_neq_ => {:"string/=", :string_neq},
    :string_neq => {:"string/=", :string_neq},
    :"string<" => {:"string<", :string_lt},
    :_cl_string_lt_ => {:"string<", :string_lt},
    :string_lt => {:"string<", :string_lt},
    :"string<=" => {:"string<=", :string_lte},
    :_cl_string_lte_ => {:"string<=", :string_lte},
    :string_lte => {:"string<=", :string_lte},
    :"string>" => {:"string>", :string_gt},
    :_cl_string_gt_ => {:"string>", :string_gt},
    :string_gt => {:"string>", :string_gt},
    :"string>=" => {:"string>=", :string_gte},
    :_cl_string_gte_ => {:"string>=", :string_gte},
    :string_gte => {:"string>=", :string_gte},
    :string_equal => {:string_equal, :string_equal},
    :string_not_equal => {:string_not_equal, :string_not_equal},
    :string_lessp => {:string_lessp, :string_lessp},
    :string_greaterp => {:string_greaterp, :string_greaterp},
    :string_upcase => {:string_upcase, :string_upcase},
    :string_downcase => {:string_downcase, :string_downcase},
    :string_capitalize => {:string_capitalize, :string_capitalize},
    :string_trim => {:string_trim, :string_trim},
    :string_left_trim => {:string_left_trim, :string_left_trim},
    :string_right_trim => {:string_right_trim, :string_right_trim},
    :string => {:string, :string},
    :char => {:char, :char},
    :schar => {:schar, :schar},
    :character => {:character, :character},
    :char_code => {:char_code, :char_code},
    :code_char => {:code_char, :code_char},
    :char_equal => {:char_equal, :char_equal},
    :char_not_equal => {:char_not_equal, :char_not_equal},
    :char_lessp => {:char_lessp, :char_lessp},
    :char_greaterp => {:char_greaterp, :char_greaterp},
    :char_not_greaterp => {:char_not_greaterp, :char_not_greaterp},
    :_cl_char_not_greaterp_ => {:char_not_greaterp, :char_not_greaterp},
    :"char-not-greaterp" => {:char_not_greaterp, :char_not_greaterp},
    :char_not_lessp => {:char_not_lessp, :char_not_lessp},
    :_cl_char_not_lessp_ => {:char_not_lessp, :char_not_lessp},
    :"char-not-lessp" => {:char_not_lessp, :char_not_lessp},
    :string_not_greaterp => {:string_not_greaterp, :string_not_greaterp},
    :_cl_string_not_greaterp_ => {:string_not_greaterp, :string_not_greaterp},
    :"string-not-greaterp" => {:string_not_greaterp, :string_not_greaterp},
    :string_not_lessp => {:string_not_lessp, :string_not_lessp},
    :_cl_string_not_lessp_ => {:string_not_lessp, :string_not_lessp},
    :"string-not-lessp" => {:string_not_lessp, :string_not_lessp},
    :nstring_upcase => {:nstring_upcase, :nstring_upcase},
    :_cl_nstring_upcase_ => {:nstring_upcase, :nstring_upcase},
    :"nstring-upcase" => {:nstring_upcase, :nstring_upcase},
    :nstring_downcase => {:nstring_downcase, :nstring_downcase},
    :_cl_nstring_downcase_ => {:nstring_downcase, :nstring_downcase},
    :"nstring-downcase" => {:nstring_downcase, :nstring_downcase},
    :nstring_capitalize => {:nstring_capitalize, :nstring_capitalize},
    :_cl_nstring_capitalize_ => {:nstring_capitalize, :nstring_capitalize},
    :"nstring-capitalize" => {:nstring_capitalize, :nstring_capitalize},
    :both_case_p => {:both_case_p, :both_case_p},
    :_cl_both_case_p_ => {:both_case_p, :both_case_p},
    :"both-case-p" => {:both_case_p, :both_case_p},
    :upper_case_p => {:upper_case_p, :upper_case_p},
    :_cl_upper_case_p_ => {:upper_case_p, :upper_case_p},
    :"upper-case-p" => {:upper_case_p, :upper_case_p},
    :lower_case_p => {:lower_case_p, :lower_case_p},
    :_cl_lower_case_p_ => {:lower_case_p, :lower_case_p},
    :"lower-case-p" => {:lower_case_p, :lower_case_p},
    :standard_char_p => {:standard_char_p, :standard_char_p},
    :_cl_standard_char_p_ => {:standard_char_p, :standard_char_p},
    :"standard-char-p" => {:standard_char_p, :standard_char_p},
    :char_upcase => {:char_upcase, :char_upcase},
    :char_downcase => {:char_downcase, :char_downcase},
    :alpha_char_p => {:alpha_char_p, :alpha_char_p},
    :_cl_alpha_char_p_ => {:alpha_char_p, :alpha_char_p},
    :"alpha-char-p" => {:alpha_char_p, :alpha_char_p},
    :graphic_char_p => {:graphic_char_p, :graphic_char_p},
    :_cl_graphic_char_p_ => {:graphic_char_p, :graphic_char_p},
    :"graphic-char-p" => {:graphic_char_p, :graphic_char_p},
    :digit_char_p => {:digit_char_p, :digit_char_p},
    :_cl_digit_char_p_ => {:digit_char_p, :digit_char_p},
    :"digit-char-p" => {:digit_char_p, :digit_char_p},
    :alphanumericp => {:alphanumericp, :alphanumericp},
    :char_name => {:char_name, :char_name},
    :_cl_char_name_ => {:char_name, :char_name},
    :name_char => {:name_char, :name_char},
    :_cl_name_char_ => {:name_char, :name_char},
    :digit_char => {:digit_char, :digit_char},
    :_cl_digit_char_ => {:digit_char, :digit_char},
    :char_int => {:char_int, :char_int},
    :_cl_char_int_ => {:char_int, :char_int},
    :int_char => {:int_char, :int_char},
    :_cl_int_char_ => {:int_char, :int_char},
    :make_string => {:make_string, :make_string},
    :_cl_make_string_ => {:make_string, :make_string},
    :"char=" => {:"char=", :char_eq},
    :_cl_char_eq_ => {:"char=", :char_eq},
    :char_eq => {:"char=", :char_eq},
    :"char/=" => {:"char/=", :char_neq},
    :_cl_char_neq_ => {:"char/=", :char_neq},
    :char_neq => {:"char/=", :char_neq},
    :"char<" => {:"char<", :char_lt},
    :_cl_char_lt_ => {:"char<", :char_lt},
    :char_lt => {:"char<", :char_lt},
    :"char<=" => {:"char<=", :char_lte},
    :_cl_char_lte_ => {:"char<=", :char_lte},
    :char_lte => {:"char<=", :char_lte},
    :"char>" => {:"char>", :char_gt},
    :_cl_char_gt_ => {:"char>", :char_gt},
    :char_gt => {:"char>", :char_gt},
    :"char>=" => {:"char>=", :char_gte},
    :_cl_char_gte_ => {:"char>=", :char_gte},
    :char_gte => {:"char>=", :char_gte},

    # I/O & formatting
    :print => {:print, :print},
    :prin1 => {:prin1, :prin1},
    :princ => {:princ, :princ},
    :write => {:write, :write},
    :write_to_string => {:write_to_string, :write_to_string},
    :_cl_write_to_string_ => {:write_to_string, :write_to_string},
    :write_line => {:write_line, :write_line},
    :_cl_write_line_ => {:write_line, :write_line},
    :write_string => {:write_string, :write_string},
    :_cl_write_string_ => {:write_string, :write_string},
    :write_char => {:write_char, :write_char},
    :_cl_write_char_ => {:write_char, :write_char},
    :read => {:read, :read},
    :read_from_string => {:read_from_string, :read_from_string},
    :_cl_read_from_string_ => {:read_from_string, :read_from_string},
    :read_line => {:read_line, :read_line},
    :_cl_read_line_ => {:read_line, :read_line},
    :read_char => {:read_char, :read_char},
    :_cl_read_char_ => {:read_char, :read_char},
    :peek_char => {:peek_char, :peek_char},
    :_cl_peek_char_ => {:peek_char, :peek_char},
    :open => {:open, :open},
    :close => {:close, :close},
    :file_length => {:file_length, :file_length},
    :_cl_file_length_ => {:file_length, :file_length},
    :listen => {:listen, :listen},
    :terpri => {:terpri, :terpri},
    :fresh_line => {:fresh_line, :fresh_line},
    :_cl_fresh_line_ => {:fresh_line, :fresh_line},
    :format => {:format, :format},
    :load => {:load, :load},
    :compile_file => {:compile_file, :compile_file},
    :_cl_compile_file_ => {:compile_file, :compile_file},
    :make_string_input_stream => {:make_string_input_stream, :make_string_input_stream},
    :_cl_make_string_input_stream_ => {:make_string_input_stream, :make_string_input_stream},
    :make_string_output_stream => {:make_string_output_stream, :make_string_output_stream},
    :_cl_make_string_output_stream_ => {:make_string_output_stream, :make_string_output_stream},
    :get_output_stream_string => {:get_output_stream_string, :get_output_stream_string},
    :_cl_get_output_stream_string_ => {:get_output_stream_string, :get_output_stream_string},
    :get_internal_real_time => {:get_internal_real_time, :get_internal_real_time},
    :_cl_get_internal_real_time_ => {:get_internal_real_time, :get_internal_real_time},
    :get_internal_run_time => {:get_internal_run_time, :get_internal_run_time},
    :_cl_get_internal_run_time_ => {:get_internal_run_time, :get_internal_run_time},
    :get_universal_time => {:get_universal_time, :get_universal_time},
    :_cl_get_universal_time_ => {:get_universal_time, :get_universal_time},

    # Symbol & package
    :gensym => {:gensym, :gensym},
    :gentemp => {:gentemp, :gentemp},
    :symbol_name => {:symbol_name, :symbol_name},
    :_cl_symbol_name_ => {:symbol_name, :symbol_name},
    :symbol_package => {:symbol_package, :symbol_package},
    :_cl_symbol_package_ => {:symbol_package, :symbol_package},
    :symbol_value => {:symbol_value, :symbol_value},
    :_cl_symbol_value_ => {:symbol_value, :symbol_value},
    :symbol_function => {:symbol_function, :symbol_function},
    :_cl_symbol_function_ => {:symbol_function, :symbol_function},
    :fdefinition => {:fdefinition, :fdefinition},
    :fmakunbound => {:fmakunbound, :fmakunbound},
    :makunbound => {:makunbound, :makunbound},
    :make_symbol => {:make_symbol, :make_symbol},
    :_cl_make_symbol_ => {:make_symbol, :make_symbol},
    :copy_symbol => {:copy_symbol, :copy_symbol},
    :_cl_copy_symbol_ => {:copy_symbol, :copy_symbol},
    :special_operator_p => {:special_operator_p, :special_operator_p},
    :_cl_special_operator_p_ => {:special_operator_p, :special_operator_p},
    :cell_error_name => {:cell_error_name, :cell_error_name},
    :_cl_cell_error_name_ => {:cell_error_name, :cell_error_name},
    :"cell-error-name" => {:cell_error_name, :cell_error_name},
    :set => {:set, :set_symbol_value},
    :symbol_plist => {:symbol_plist, :symbol_plist},
    :_cl_symbol_plist_ => {:symbol_plist, :symbol_plist},
    :get => {:get, :get_symbol_prop},
    :remprop => {:remprop, :remprop},
    :intern => {:intern, :intern},
    :find_symbol => {:find_symbol, :find_symbol},
    :_cl_find_symbol_ => {:find_symbol, :find_symbol},
    :defpackage => {:defpackage, :defpackage},
    :in_package => {:in_package, :in_package},
    :_cl_in_package_ => {:in_package, :in_package},
    :find_package => {:find_package, :find_package},
    :_cl_find_package_ => {:find_package, :find_package},

    # Bitwise & math operations
    :logand => {:logand, :logand},
    :_cl_logand_ => {:logand, :logand},
    :logior => {:logior, :logior},
    :_cl_logior_ => {:logior, :logior},
    :logxor => {:logxor, :logxor},
    :_cl_logxor_ => {:logxor, :logxor},
    :lognot => {:lognot, :lognot},
    :_cl_lognot_ => {:lognot, :lognot},
    :logeqv => {:logeqv, :logeqv},
    :_cl_logeqv_ => {:logeqv, :logeqv},
    :lognand => {:lognand, :lognand},
    :_cl_lognand_ => {:lognand, :lognand},
    :lognor => {:lognor, :lognor},
    :_cl_lognor_ => {:lognor, :lognor},
    :logandc1 => {:logandc1, :logandc1},
    :_cl_logandc1_ => {:logandc1, :logandc1},
    :logandc2 => {:logandc2, :logandc2},
    :_cl_logandc2_ => {:logandc2, :logandc2},
    :logorc1 => {:logorc1, :logorc1},
    :_cl_logorc1_ => {:logorc1, :logorc1},
    :logorc2 => {:logorc2, :logorc2},
    :_cl_logorc2_ => {:logorc2, :logorc2},
    :ash => {:ash, :ash},
    :_cl_ash_ => {:ash, :ash},
    :logbitp => {:logbitp, :logbitp},
    :_cl_logbitp_ => {:logbitp, :logbitp},
    :logcount => {:logcount, :logcount},
    :_cl_logcount_ => {:logcount, :logcount},
    :integer_length => {:integer_length, :integer_length},
    :_cl_integer_length_ => {:integer_length, :integer_length},
    :isqrt => {:isqrt, :isqrt},
    :_cl_isqrt_ => {:isqrt, :isqrt},
    :byte => {:byte, :byte},
    :_cl_byte_ => {:byte, :byte},
    :ldb => {:ldb, :ldb},
    :_cl_ldb_ => {:ldb, :ldb},
    :dpb => {:dpb, :dpb},
    :_cl_dpb_ => {:dpb, :dpb},
    :boole => {:boole, :boole},
    :_cl_boole_ => {:boole, :boole},
    :logtest => {:logtest, :logtest},
    :_cl_logtest_ => {:logtest, :logtest},
    :signum => {:signum, :signum},
    :_cl_signum_ => {:signum, :signum},
    :parse_integer => {:parse_integer, :parse_integer},
    :_cl_parse_integer_ => {:parse_integer, :parse_integer},
    :random => {:random, :random},
    :_cl_random_ => {:random, :random},
    :make_random_state => {:make_random_state, :make_random_state},
    :_cl_make_random_state_ => {:make_random_state, :make_random_state},

    # Utilities, error handling & REPL history
    :eval => {:eval, :eval},
    :_cl_eval_ => {:eval, :eval},
    :compile => {:compile, :compile},
    :_cl_compile_ => {:compile, :compile},
    :identity => {:identity, :identity},
    :_cl_identity_ => {:identity, :identity},
    :constantly => {:constantly, :constantly},
    :_cl_constantly_ => {:constantly, :constantly},
    :complement => {:complement, :complement},
    :_cl_complement_ => {:complement, :complement},
    :values => {:values, :values},
    :_cl_values_ => {:values, :values},
    :values_list => {:values_list, :values_list},
    :_cl_values_list_ => {:values_list, :values_list},
    :funcall => {:funcall, :funcall},
    :_cl_funcall_ => {:funcall, :funcall},
    :apply => {:apply, :apply},
    :_cl_apply_ => {:apply, :apply},
    :error => {:error, :error},
    :cerror => {:cerror, :cerror},
    :warn => {:warn, :warn},
    :r => {:r, :r},
    :v => {:v, :v},

    # Property lists & macro expansion
    :getf => {:getf, :getf},
    :exlisp_check_key_args => {:exlisp_check_key_args, :exlisp_check_key_args},
    :macro_function => {:macro_function, :macro_function},
    :_cl_macro_function_ => {:macro_function, :macro_function},
    :macroexpand_1 => {:macroexpand_1, :macroexpand_1},
    :_cl_macroexpand_1_ => {:macroexpand_1, :macroexpand_1},
    :macroexpand => {:macroexpand, :macroexpand},
    :_cl_macroexpand_ => {:macroexpand, :macroexpand},

    # Packages & system operations
    :export => {:export, :export},
    :use_package => {:use_package, :use_package},
    :_cl_use_package_ => {:use_package, :use_package},
    :shadow => {:shadow, :shadow},
    :shadowing_import => {:shadowing_import, :shadowing_import},
    :_cl_shadowing_import_ => {:shadowing_import, :shadowing_import},
    :import => {:import, :import},
    :provide => {:provide, :provide},
    :require => {:require, :require},

    # Quicklisp & ASDF
    :quickload => {:quickload, :quickload},
    :_cl_quickload_ => {:quickload, :quickload},
    :"ql.quickload" => {:quickload, :quickload},
    :"ql:quickload" => {:quickload, :quickload},
    :"asdf.load_system" => {:quickload, :quickload},
    :"asdf:load-system" => {:quickload, :quickload},
    :system_apropos => {:system_apropos, :system_apropos},
    :"ql.system_apropos" => {:system_apropos, :system_apropos},
    :"ql:system-apropos" => {:system_apropos, :system_apropos},
    :where_is_system => {:where_is_system, :where_is_system},
    :"ql.where_is_system" => {:where_is_system, :where_is_system},
    :"ql:where-is-system" => {:where_is_system, :where_is_system},

    # Hex.pm
    :hex_install => {:hex_install, :hex_install},
    :_cl_hex_install_ => {:hex_install, :hex_install},
    :"hex.install" => {:hex_install, :hex_install},
    :"hex:install" => {:hex_install, :hex_install},
    :hex_search => {:hex_search, :hex_search},
    :_cl_hex_search_ => {:hex_search, :hex_search},
    :"hex.search" => {:hex_search, :hex_search},
    :"hex:search" => {:hex_search, :hex_search},
    :hex_info => {:hex_info, :hex_info},
    :_cl_hex_info_ => {:hex_info, :hex_info},
    :"hex.info" => {:hex_info, :hex_info},
    :"hex:info" => {:hex_info, :hex_info},
    :hex_where_is_package => {:hex_where_is_package, :hex_where_is_package},
    :_cl_hex_where_is_package_ => {:hex_where_is_package, :hex_where_is_package},
    :"hex.where_is_package" => {:hex_where_is_package, :hex_where_is_package},
    :"hex:where_is_package" => {:hex_where_is_package, :hex_where_is_package},
    :"hex:where-is-package" => {:hex_where_is_package, :hex_where_is_package},

    # SBCL quit & exit
    :quit => {:quit, :quit},
    :_cl_quit_ => {:quit, :quit},
    :exit => {:quit, :quit},
    :_cl_exit_ => {:quit, :quit},
    :"sb-ext:quit" => {:quit, :quit},
    :"sb_ext:quit" => {:quit, :quit},
    :"sb-ext.quit" => {:quit, :quit},
    :"sb_ext.quit" => {:quit, :quit},
    :"sb-ext::quit" => {:quit, :quit},
    :"sb_ext::quit" => {:quit, :quit},
    :"sb-ext:exit" => {:quit, :quit},
    :"sb_ext:exit" => {:quit, :quit},
    :"sb-ext.exit" => {:quit, :quit},
    :"sb_ext.exit" => {:quit, :quit},
    :"sb-ext::exit" => {:quit, :quit},
    :"sb_ext::exit" => {:quit, :quit},

    # Internal helpers
    :_cl_set_elt_update_seq_ => {:set_elt_update_seq, :set_elt_update_seq},
    :set_elt_update_seq => {:set_elt_update_seq, :set_elt_update_seq},
    :_cl_set_subseq_update_seq_ => {:set_subseq_update_seq, :set_subseq_update_seq},
    :set_subseq_update_seq => {:set_subseq_update_seq, :set_subseq_update_seq}
  }

  @doc """
  Returns the list of defined built-in function atoms.
  """
  def builtins do
    @builtin_mappings
    |> Map.values()
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  @doc """
  Returns the canonicalized atom name for the given operator.
  """
  def canonical_name(name) when is_binary(name) do
    down_str = String.downcase(name)

    stripped_str =
      case String.split(down_str, ~r/::?|\./, parts: 2) do
        [pkg, sym] when pkg in ["cl", "common-lisp", "common_lisp", "sb-cl", "sb_cl"] -> sym
        _ -> down_str
      end

    atom = String.to_atom(stripped_str)
    canonical_name(atom)
  end

  def canonical_name(atom) when is_atom(atom) do
    str = atom |> Atom.to_string() |> String.downcase()

    stripped_str =
      case String.split(str, ~r/::?|\./, parts: 2) do
        [pkg, sym] when pkg in ["cl", "common-lisp", "common_lisp", "sb-cl", "sb_cl"] -> sym
        _ -> str
      end

    down_atom = String.to_atom(stripped_str)

    case Map.get(@builtin_mappings, down_atom) do
      {canonical, _impl} ->
        {:ok, canonical}

      nil ->
        replaced = stripped_str |> String.replace("-", "_") |> String.to_atom()

        case Map.get(@builtin_mappings, replaced) do
          {canonical, _impl} -> {:ok, canonical}
          nil -> :error
        end
    end
  end

  def canonical_name(_), do: :error

  @doc """
  Determines whether the given operator is a built-in function.
  Returns `{:ok, atom_name}` if it is a built-in function, `:error` otherwise.
  """
  def lookup({:id, _pos, [name]}) when is_binary(name) do
    lookup(name)
  end

  def lookup({:id, _pos, parts}) when is_list(parts) do
    str = Enum.join(parts, ".")

    case canonical_name(str) do
      {:ok, _} = res ->
        res

      :error ->
        colon_str = Enum.join(parts, ":")
        canonical_name(colon_str)
    end
  end

  def lookup(name) when is_binary(name) do
    canonical_name(name)
  end

  def lookup({:lit, atom}) when is_atom(atom) do
    lookup(atom)
  end

  def lookup(op) when is_atom(op) do
    canonical_name(op)
  end

  def lookup(_), do: :error

  @doc """
  Returns a boolean indicating whether the given operator is a built-in function.
  """
  def builtin?(op) do
    case lookup(op) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Compiles a built-in function call to Erlang Abstract Format.
  Receives `compile_expr_fn` callback to compile argument expressions.
  """
  def compile(op, args, compile_expr_fn) when is_function(compile_expr_fn, 1) do
    norm_op =
      case lookup(op) do
        {:ok, canonical} ->
          canonical

        :error ->
          if is_atom(op), do: op, else: String.to_atom(to_string(op))
      end

    case norm_op do
      # Addition: (+ 1 2)
      :+ ->
        compiled_args = Enum.map(args, compile_expr_fn)
        compile_builtin_call(:add, compiled_args)

      # Subtraction: (- 5 2)
      :- ->
        case args do
          [] ->
            raise ArgumentError, "- requires at least 1 argument"

          _ ->
            compiled_args = Enum.map(args, compile_expr_fn)
            compile_builtin_call(:sub, compiled_args)
        end

      # Multiplication: (* 3 4)
      :* ->
        compiled_args = Enum.map(args, compile_expr_fn)
        compile_builtin_call(:mul, compiled_args)

      # Division: (/ 10 2)
      :/ ->
        case args do
          [] ->
            raise ArgumentError, "/ requires at least 1 argument"

          _ ->
            compiled_args = Enum.map(args, compile_expr_fn)
            compile_builtin_call(:divide, compiled_args)
        end

      # Cons cell creation: (cons 1 [2 3])
      :cons ->
        case args do
          [head, tail] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :cons}},
             [compile_expr_fn.(head), compile_expr_fn.(tail)]}

          _ ->
            raise ArgumentError, "cons requires exactly 2 arguments, got #{length(args)}"
        end

      # List creation: (list 1 2 3)
      :list ->
        ast_cons_list(Enum.map(args, compile_expr_fn))

      _ ->
        case Map.get(@builtin_mappings, norm_op) do
          nil ->
            raise "Unsupported builtin function: #{inspect(op)}"

          {_canonical, impl_name} ->
            compiled_args = Enum.map(args, compile_expr_fn)
            compile_builtin_call(impl_name, compiled_args)
        end
    end
  end

  defp compile_builtin_call(impl_name, compiled_args) do
    case {impl_name, compiled_args} do
      {:add, []} ->
        {:integer, 1, 0}

      {:add, [single]} ->
        single

      {:add, [a, b]} ->
        compile_inline_math_2(:+, :add_two, a, b)

      {:sub, [single]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :negate_num}}, [single]}

      {:sub, [a, b]} ->
        compile_inline_math_2(:-, :sub_two, a, b)

      {:mul, []} ->
        {:integer, 1, 1}

      {:mul, [single]} ->
        single

      {:mul, [a, b]} ->
        compile_inline_math_2(:*, :mul_two, a, b)

      {:divide, [single]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :divide_two}},
         [{:integer, 1, 1}, single]}

      {:divide, [a, b]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :divide_two}}, [a, b]}

      {:one_plus, [single]} ->
        compile_inline_math_2(:+, :add_two, single, {:integer, 1, 1})

      {:one_minus, [single]} ->
        compile_inline_math_2(:-, :sub_two, single, {:integer, 1, 1})

      {:num_lte, [a, b]} ->
        compile_inline_cmp_2(:"=<", :num_lte_two, a, b)

      {:num_lt, [a, b]} ->
        compile_inline_cmp_2(:<, :num_lt_two, a, b)

      {:num_gte, [a, b]} ->
        compile_inline_cmp_2(:>=, :num_gte_two, a, b)

      {:num_gt, [a, b]} ->
        compile_inline_cmp_2(:>, :num_gt_two, a, b)

      {:num_eq, [a, b]} ->
        compile_inline_cmp_2(:==, :num_eq_two, a, b)

      {:num_neq, [a, b]} ->
        compile_inline_cmp_2(:"/=", :num_neq_two, a, b)

      {:eq, [a, b]} ->
        {:case, 1, {:op, 1, :"=:=", a, b},
         [
           {:clause, 1, [{:atom, 1, true}], [], [{:atom, 1, :t}]},
           {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]}
         ]}

      {:eql, [a, b]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :eql}}, [a, b]}

      {:aref, [arr, idx]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :aref}}, [arr, idx]}

      {:mapcar, [f, l]} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :mapcar}}, [f, l]}

      _ ->
        do_compile_builtin_call(impl_name, compiled_args)
    end
  end

  defp compile_inline_math_2(op, fallback_fn, a, b) do
    v1 = :"V_math1_#{System.unique_integer([:positive, :monotonic])}"
    v2 = :"V_math2_#{System.unique_integer([:positive, :monotonic])}"

    {:case, 1, a,
     [
       {:clause, 1, [{:var, 1, v1}], [[{:call, 1, {:atom, 1, :is_integer}, [{:var, 1, v1}]}]],
        [
          {:case, 1, b,
           [
             {:clause, 1, [{:var, 1, v2}],
              [[{:call, 1, {:atom, 1, :is_integer}, [{:var, 1, v2}]}]],
              [{:op, 1, op, {:var, 1, v1}, {:var, 1, v2}}]},
             {:clause, 1, [{:var, 1, v2}], [],
              [
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
                 [{:var, 1, v1}, {:var, 1, v2}]}
              ]}
           ]}
        ]},
       {:clause, 1, [{:var, 1, v1}], [[{:call, 1, {:atom, 1, :is_float}, [{:var, 1, v1}]}]],
        [
          {:case, 1, b,
           [
             {:clause, 1, [{:var, 1, v2}], [[{:call, 1, {:atom, 1, :is_float}, [{:var, 1, v2}]}]],
              [{:op, 1, op, {:var, 1, v1}, {:var, 1, v2}}]},
             {:clause, 1, [{:var, 1, v2}], [],
              [
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
                 [{:var, 1, v1}, {:var, 1, v2}]}
              ]}
           ]}
        ]},
       {:clause, 1, [{:var, 1, v1}], [],
        [
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
           [{:var, 1, v1}, b]}
        ]}
     ]}
  end

  defp compile_inline_cmp_2(op, fallback_fn, a, b) do
    v1 = :"V_cmp1_#{System.unique_integer([:positive, :monotonic])}"
    v2 = :"V_cmp2_#{System.unique_integer([:positive, :monotonic])}"

    {:case, 1, a,
     [
       {:clause, 1, [{:var, 1, v1}], [[{:call, 1, {:atom, 1, :is_integer}, [{:var, 1, v1}]}]],
        [
          {:case, 1, b,
           [
             {:clause, 1, [{:var, 1, v2}],
              [[{:call, 1, {:atom, 1, :is_integer}, [{:var, 1, v2}]}]],
              [
                {:case, 1, {:op, 1, op, {:var, 1, v1}, {:var, 1, v2}},
                 [
                   {:clause, 1, [{:atom, 1, true}], [], [{:atom, 1, :t}]},
                   {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]}
                 ]}
              ]},
             {:clause, 1, [{:var, 1, v2}], [],
              [
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
                 [{:var, 1, v1}, {:var, 1, v2}]}
              ]}
           ]}
        ]},
       {:clause, 1, [{:var, 1, v1}], [[{:call, 1, {:atom, 1, :is_float}, [{:var, 1, v1}]}]],
        [
          {:case, 1, b,
           [
             {:clause, 1, [{:var, 1, v2}], [[{:call, 1, {:atom, 1, :is_float}, [{:var, 1, v2}]}]],
              [
                {:case, 1, {:op, 1, op, {:var, 1, v1}, {:var, 1, v2}},
                 [
                   {:clause, 1, [{:atom, 1, true}], [], [{:atom, 1, :t}]},
                   {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]}
                 ]}
              ]},
             {:clause, 1, [{:var, 1, v2}], [],
              [
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
                 [{:var, 1, v1}, {:var, 1, v2}]}
              ]}
           ]}
        ]},
       {:clause, 1, [{:var, 1, v1}], [],
        [
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, fallback_fn}},
           [{:var, 1, v1}, b]}
        ]}
     ]}
  end

  defp do_compile_builtin_call(impl_name, compiled_args) do
    case impl_name do
      name
      when name in [
             :add,
             :sub,
             :mul,
             :divide,
             :num_eq,
             :num_neq,
             :num_lt,
             :num_lte,
             :num_gt,
             :num_gte,
             :min,
             :max,
             :gcd,
             :lcm,
             :append,
             :nconc,
             :list,
             :list_star,
             :open,
             :read,
             :read_from_string,
             :read_line,
             :read_char,
             :peek_char,
             :write,
             :make_hash_table,
             :make_array,
             :adjust_array,
             :coerce,
             :complex,
             :vector,
             :aref,
             :make_instance,
             :warn,
             :cerror,
             :gensym,
             :gentemp,
             :make_symbol,
             :copy_symbol,
             :special_operator_p,
             :defpackage,
             :in_package,
             :find_package,
             :logand,
             :logior,
             :logxor,
             :logeqv,
             :r,
             :v,
             :append,
             :values,
             :map,
             :every,
             :some,
             :notany,
             :notevery,
             :position,
             :position_if,
             :position_if_not,
             :find,
             :find_if,
             :find_if_not,
             :count,
             :count_if,
             :count_if_not,
             :string_upcase,
             :string_downcase,
             :string_capitalize,
             :nstring_upcase,
             :nstring_downcase,
             :nstring_capitalize,
             :string_trim,
             :string_left_trim,
             :string_right_trim,
             :array_has_fill_pointer_p,
             :adjustable_array_p,
             :remove,
             :remove_if,
             :remove_if_not,
             :remove_duplicates,
             :delete_duplicates,
             :substitute,
             :substitute_if,
             :substitute_if_not,
             :mismatch,
             :fill,
             :replace,
             :char_eq,
             :char_neq,
             :char_lt,
             :char_lte,
             :char_gt,
             :char_gte,
             :char_equal,
             :char_not_equal,
             :char_lessp,
             :char_greaterp,
             :char_not_greaterp,
             :char_not_lessp,
             :string_not_greaterp,
             :string_not_lessp,
             :string_eq,
             :string_neq,
             :string_lt,
             :string_lte,
             :string_gt,
             :string_gte,
             :string_equal,
             :string_not_equal,
             :string_lessp,
             :string_greaterp,
             :union,
             :nunion,
             :intersection,
             :nintersection,
             :set_difference,
             :nset_difference,
             :set_exclusive_or,
             :nset_exclusive_or,
             :subsetp,
             :member,
             :member_if,
             :member_if_not,
             :assoc,
             :assoc_if,
             :assoc_if_not,
             :rassoc,
             :rassoc_if,
             :rassoc_if_not,
             :adjoin,
             :subst,
             :nsubst,
             :subst_if,
             :nsubst_if,
             :subst_if_not,
             :nsubst_if_not,
             :sublis,
             :nsublis,
             :tree_equal,
             :pairlis,
             :copy_list,
             :copy_alist,
             :copy_tree,
             :revappend,
             :nreconc,
             :tailp,
             :ldiff,
             :last,
             :butlast,
             :nbutlast,
             :getf,
             :remf,
             :get_properties,
             :mapc,
             :mapcar,
             :mapcan,
             :maplist,
             :mapl,
             :mapcon,
             :make_list,
             :make_sequence,
             :concatenate,
             :search,
             :map_into,
             :map,
             :reduce,
             :merge,
             :sort,
             :stable_sort,
             :delete,
             :delete_if,
             :delete_if_not,
             :nsubstitute,
             :nsubstitute_if,
             :nsubstitute_if_not,
             :subseq,
             :array_row_major_index,
             :compile,
             :export,
             :use_package,
             :shadow,
             :shadowing_import,
             :import,
             :provide,
             :require,
             :parse_integer,
             :make_string,
             :make_string_output_stream,
             :quickload,
             :system_apropos,
             :where_is_system,
             :hex_install,
             :hex_search,
             :hex_info,
             :hex_where_is_package,
             :quit
           ] ->
        args_cons = ast_cons_list(compiled_args)

        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, impl_name}}, [args_cons]}

      :mapcar ->
        case compiled_args do
          [fn_arg, list_arg] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :mapcar}},
             [fn_arg, list_arg]}

          [fn_arg | rest_lists] ->
            lists_cons = ast_cons_list(rest_lists)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :mapcar}},
             [fn_arg, lists_cons]}

          _ ->
            raise ArgumentError, "mapcar requires at least 2 arguments"
        end

      :mapc ->
        case compiled_args do
          [fn_arg, list_arg] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :mapc}},
             [fn_arg, list_arg]}

          [fn_arg | rest_lists] ->
            lists_cons = ast_cons_list(rest_lists)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :mapc}},
             [fn_arg, lists_cons]}

          _ ->
            raise ArgumentError, "mapc requires at least 2 arguments"
        end

      :format ->
        case compiled_args do
          [dest, fmt | rest] ->
            rest_cons = ast_cons_list(rest)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :format}},
             [dest, fmt, rest_cons]}

          _ ->
            raise ArgumentError, "format requires at least 2 arguments"
        end

      :funcall ->
        case compiled_args do
          [fn_arg | rest_args] ->
            args_cons = ast_cons_list(rest_args)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :funcall}},
             [fn_arg, args_cons]}

          _ ->
            raise ArgumentError, "funcall requires at least 1 argument"
        end

      :apply ->
        case compiled_args do
          [fn_arg | rest_args] ->
            args_cons = ast_cons_list(rest_args)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :apply}},
             [fn_arg, args_cons]}

          _ ->
            raise ArgumentError, "apply requires at least 1 argument"
        end

      _ ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, impl_name}},
         compiled_args}
    end
  end

  defp ast_cons_list(list, tail \\ {nil, 1}) do
    Enum.reduce(Enum.reverse(list), tail, fn elem, acc ->
      {:cons, 1, elem, acc}
    end)
  end
end
