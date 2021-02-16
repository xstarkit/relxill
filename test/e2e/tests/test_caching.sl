require("load_test_setup.sl","Global");
% -*- mode: slang; mode: fold -*-

variable msg_log = "";


define test_caching_spec(v,v0,inp,inp0){ %{{{
   variable ii, n = length(v);
   variable status = EXIT_SUCCESS;
   
   variable lim = 1e-8;
   variable tmp;
   
   % #1# for v each spectrum should be different
   _for ii(0,n-2,1){
      tmp = sum(  (v[ii] - v[ii+1] )^2 ) ;
      if (tmp < lim ){
	 vmessage("     caching spectra not correct (did not change while it should), %.3e < %.3e for values %.2e and %.2e ",
		  tmp, lim, inp[ii], inp[ii+1] );
	 return EXIT_FAILURE;
      }
      
   }
   
   % #2# for v0 each spectrum should be the same
   _for ii(0,n-2,1){
      tmp = sum(  (v0[ii] - v0[ii+1] )^2 );
      if (tmp > lim){
	 vmessage(" *** caching spectra not correct (did change while it should NOT), %.3e > %.3e", tmp, lim);
	 return EXIT_FAILURE;
      }
      
   }

   % #3# by design the last elements should be the same
   tmp = sum(  (v[-1] - v0[-1] )^2 );
   if (tmp > lim){
      vmessage(" *** caching spectra not correct (spectra are different while they should NOT), %.3e > %.3e", tmp, lim);
      return EXIT_FAILURE;
   }
   
   
   return EXIT_SUCCESS;
}
%}}}

define check_caching_single(ff,par){ %{{{

   fit_fun_default(ff);   
   variable param0 = get_params("*."+par);
   if (length(param0)!=1){
      vmessage(" *** error *** problem with model %s and parameter %s when testing caching",ff,par);
      return EXIT_FAILURE;
   }
   variable p = param0[0];
   % clone parameter

   % ### 1 ### change parameter between min and max
   variable N = 10;
   variable v;
   
   variable vals;

   %% make sure we get useful values of p.value==0
   if (p.value < 0.1 && p.value >= 0){
      p.value = 0.1;
   }
   
   if (abs(p.value-p.min) < abs(p.max-p.value)){
      vals = [p.value:p.value*1.2 :#N];
   } else {
      if (p.value>=0){
	 vals = [p.value*0.8:p.value:#N];
      } else {
	 vals = [p.value:p.value*1.2 :#N];	 
      }
   }

   variable vals0 = vals*0 + vals[-1];  %% DO NOT CHANGE THIS (will be used later)
   
   %% make sure values of the table are loaded before such that we do
   %% not count the loading of the table as well here
   foreach v(vals){
      set_par(p.name,v);
      () = eval_fun_keV(lo0,hi0);
   }
   
   variable val_ncache = Array_Type[N];				      
   variable val0_cache = Array_Type[N];				      

   %% special cases %%
   if (string_match(p.name,`.*\.Rbr`)){
      set_par("*.Index1",3.5);
   }
   %% %%%%%%%%%%%%% %%
   
   variable ii;
   tic;
   _for ii(0,N-1){
      set_par(p.name,vals[ii]);
      val_ncache[ii] = eval_fun_keV(lo0,hi0);
   }
   variable dt = toc;

   tic;
   _for ii(0,N-1){
      set_par(p.name,vals0[ii]);
      val0_cache[ii] = eval_fun_keV(lo0,hi0);
   }
   variable dt2 = toc;

   variable no_cache_msec = dt/N*1e3;
   variable cache_msec = dt2/N*1e3;
   
   
   variable res = struct{no_cache=no_cache_msec, cache=cache_msec};
   
   if (test_caching_spec(val_ncache,val0_cache,vals,vals0) != EXIT_SUCCESS){
      msg_log += sprintf("     => spectra did not behave as expected when testing caching (%s -  %s)\n",ff,par);
      return EXIT_FAILURE, res;
   } else {
      if (cache_msec < 500.0){
	 msg_log +=sprintf("   --> %.1f ms vs. %.1f ms  --  (%s -  %s)\n",no_cache_msec, cache_msec,ff,par );
      } else {	 
	 msg_log +=sprintf("   --> *** FAILED ***  [ %.1f ms vs. %.1f ms ] --  (%s -  %s) \n",no_cache_msec, cache_msec,ff,par );	       
	 return EXIT_FAILURE, res;
      }
   }
   
   
   return EXIT_SUCCESS, res;
}
%}}}


define check_single_model(ff,params){
   variable ii, n;
   n = length(params);
   variable status, res;
   variable avg_no_cache = 0.0;
   variable avg_cache = 0.0;
   _for ii(0,n-1){
      (status, res ) = check_caching_single(ff,params[ii];nopl);
      if ( status == EXIT_FAILURE){
	 vmessage(" *** error: there seems to be a problem with the CACHING for model %s and parameter %s",
		  ff,params[ii]);
	 return EXIT_FAILURE;
      }
      
      avg_no_cache += res.no_cache/n;
      avg_cache += res.cache/n;
      
   }      

   variable msg_summary = sprintf(" %s ==> %.1f ms vs. %.1f ms\n", ff, avg_no_cache, avg_cache);
   msg_log += msg_summary;
%   if (verbose){
   () = printf(msg_summary);
   %   }
   
   return EXIT_SUCCESS;
}


define runtest(ffs){ 

   counter++;
   msg_log += sprintf(" testing CACHING for following models\n");
   
   variable ff_arr = Assoc_Type[Array_Type];
   
   variable std_rel_param = ["a","Incl","Rin"];
   variable std_xill_param = ["logxi","Afe","z"];
   
%   ff_arr["relxilllpionCp"] = [std_rel_param, "h","refl_frac", std_xill_param, "xi_index",  "kTe"];
   ff_arr["relxilllpion"] = [std_rel_param, "h","refl_frac", std_xill_param, "xi_index" ];
%   ff_arr["relline"]   = [std_rel_param, "Rbr" , "Index1","Index2"];
%   ff_arr["relline_lp"]   = [std_rel_param, "h"];
   ff_arr["relxill"]   = [std_rel_param, "Index1",std_xill_param, "Ecut"];
   ff_arr["relxilllp"] = [std_rel_param, "h","refl_frac", std_xill_param, "Ecut" ];
%   ff_arr["relxillD"]   = [std_rel_param, "Rbr", "Index1","Index2", std_xill_param, "logN" ];
   ff_arr["relxilllpD"] = [std_rel_param, "h","refl_frac", std_xill_param, "logN" ];
#ifndef STABLE
   ff_arr["relxillCO"] = [std_rel_param, "A_CO", "frac_pl_bb", "kTbb"];
   ff_arr["relxillNS"] = [std_rel_param, "logN", "kTbb"];
#endif
   
   variable ff, params;
   variable status = EXIT_SUCCESS;
   foreach ff(assoc_get_keys(ff_arr)){
      params = ff_arr[ff];
      
      if (check_single_model(ff, params) == EXIT_FAILURE){
	 return EXIT_FAILURE;
      }
      
   }
   return EXIT_SUCCESS;   
}
%}}}




