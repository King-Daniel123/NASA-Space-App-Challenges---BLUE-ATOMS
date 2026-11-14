var pas = { $libimports: {}};

var rtl = {

  version: 30200,

  quiet: false,
  debug_load_units: false,
  debug_rtti: false,

  $res : {},

  debug: function(){
    if (rtl.quiet || !console || !console.log) return;
    console.log(arguments);
  },

  error: function(s){
    rtl.debug('Error: ',s);
    throw s;
  },

  warn: function(s){
    rtl.debug('Warn: ',s);
  },

  checkVersion: function(v){
    if (rtl.version != v) throw "expected rtl version "+v+", but found "+rtl.version;
  },

  hiInt: Math.pow(2,53),

  hasString: function(s){
    return rtl.isString(s) && (s.length>0);
  },

  isArray: function(a) {
    return Array.isArray(a);
  },

  isFunction: function(f){
    return typeof(f)==="function";
  },

  isModule: function(m){
    return rtl.isObject(m) && rtl.hasString(m.$name) && (pas[m.$name]===m);
  },

  isImplementation: function(m){
    return rtl.isObject(m) && rtl.isModule(m.$module) && (m.$module.$impl===m);
  },

  isNumber: function(n){
    return typeof(n)==="number";
  },

  isObject: function(o){
    var s=typeof(o);
    return (typeof(o)==="object") && (o!=null);
  },

  isString: function(s){
    return typeof(s)==="string";
  },

  getNumber: function(n){
    return typeof(n)==="number"?n:NaN;
  },

  getChar: function(c){
    return ((typeof(c)==="string") && (c.length===1)) ? c : "";
  },

  getObject: function(o){
    return ((typeof(o)==="object") || (typeof(o)==='function')) ? o : null;
  },

  isTRecord: function(type){
    return (rtl.isObject(type) && type.hasOwnProperty('$new') && (typeof(type.$new)==='function'));
  },

  isPasClass: function(type){
    return (rtl.isObject(type) && type.hasOwnProperty('$classname') && rtl.isObject(type.$module));
  },

  isPasClassInstance: function(type){
    return (rtl.isObject(type) && rtl.isPasClass(type.$class));
  },

  hexStr: function(n,digits){
    return ("000000000000000"+n.toString(16).toUpperCase()).slice(-digits);
  },

  m_loading: 0,
  m_loading_intf: 1,
  m_intf_loaded: 2,
  m_loading_impl: 3, // loading all used unit
  m_initializing: 4, // running initialization
  m_initialized: 5,

  module: function(module_name, intfuseslist, intfcode, impluseslist){
    if (rtl.debug_load_units) rtl.debug('rtl.module name="'+module_name+'" intfuses='+intfuseslist+' impluses='+impluseslist);
    if (!rtl.hasString(module_name)) rtl.error('invalid module name "'+module_name+'"');
    if (!rtl.isArray(intfuseslist)) rtl.error('invalid interface useslist of "'+module_name+'"');
    if (!rtl.isFunction(intfcode)) rtl.error('invalid interface code of "'+module_name+'"');
    if (!(impluseslist==undefined) && !rtl.isArray(impluseslist)) rtl.error('invalid implementation useslist of "'+module_name+'"');

    if (pas[module_name])
      rtl.error('module "'+module_name+'" is already registered');

    var r = Object.create(rtl.tSectionRTTI);
    var module = r.$module = pas[module_name] = {
      $name: module_name,
      $intfuseslist: intfuseslist,
      $impluseslist: impluseslist,
      $state: rtl.m_loading,
      $intfcode: intfcode,
      $implcode: null,
      $impl: null,
      $rtti: r
    };
    if (impluseslist) module.$impl = {
          $module: module,
          $rtti: r
        };
  },

  exitcode: 0,

  run: function(module_name){
    try {
      if (!rtl.hasString(module_name)) module_name='program';
      if (rtl.debug_load_units) rtl.debug('rtl.run module="'+module_name+'"');
      rtl.initRTTI();
      var module = pas[module_name];
      if (!module) rtl.error('rtl.run module "'+module_name+'" missing');
      rtl.loadintf(module);
      rtl.loadimpl(module);
      if ((module_name=='program') || (module_name=='library')){
        if (rtl.debug_load_units) rtl.debug('running $main');
        var r = pas[module_name].$main();
        if (rtl.isNumber(r)) rtl.exitcode = r;
      }
    } catch(re) {
      if (!rtl.showUncaughtExceptions) {
        throw re
      } else {  
        if (!rtl.handleUncaughtException(re)) {
          rtl.showException(re);
          rtl.exitcode = 216;
        }  
      }
    } 
    return rtl.exitcode;
  },
  
  showException : function (re) {
    var errStack="";
    if (rtl.isObject(re) && re.hasOwnProperty('FJSError') && rtl.isObject(re.FJSError) && !(re.FJSError.stack==undefined)) // rtl Exception
      errStack=re.FJSError.stack
    else if (rtl.isObject(re) && re.hasOwnProperty('stack') && !(re.stack==undefined)) // native JS Error
      errStack=re.stack
    else
      errStack=re; // unknown object
    var errMsg = rtl.hasString(re.$classname) ? re.$classname : '';
    errMsg += ((errMsg) ? ': ' : '') + (re.hasOwnProperty('fMessage') ? re.fMessage : '');
    errMsg += ((errMsg) ? "\n" : '') + errStack;
    errMsg = "Uncaught Exception:\n" + errMsg;
    console.log(errMsg);
    alert(errMsg);
  },

  handleUncaughtException: function (e) {
    if (rtl.onUncaughtException) {
      try {
        rtl.onUncaughtException(e);
        return true;
      } catch (ee) {
        return false; 
      }
    } else {
      return false;
    }
  },

  loadintf: function(module){
    if (module.$state>rtl.m_loading_intf) return; // already finished
    if (rtl.debug_load_units) rtl.debug('loadintf: "'+module.$name+'"');
    if (module.$state===rtl.m_loading_intf)
      rtl.error('unit cycle detected "'+module.$name+'"');
    module.$state=rtl.m_loading_intf;
    // load interfaces of interface useslist
    rtl.loaduseslist(module,module.$intfuseslist,rtl.loadintf);
    // run interface
    if (rtl.debug_load_units) rtl.debug('loadintf: run intf of "'+module.$name+'"');
    module.$intfcode(module.$intfuseslist);
    // success
    module.$state=rtl.m_intf_loaded;
    // Note: units only used in implementations are not yet loaded (not even their interfaces)
  },

  loaduseslist: function(module,useslist,f){
    if (useslist==undefined) return;
    var len = useslist.length;
    for (var i = 0; i<len; i++) {
      var unitname=useslist[i];
      if (rtl.debug_load_units) rtl.debug('loaduseslist of "'+module.$name+'" uses="'+unitname+'"');
      if (pas[unitname]==undefined)
        rtl.error('module "'+module.$name+'" misses "'+unitname+'"');
      f(pas[unitname]);
    }
  },

  loadimpl: function(module){
    if (module.$state>=rtl.m_loading_impl) return; // already processing
    if (module.$state<rtl.m_intf_loaded) rtl.error('loadimpl: interface not loaded of "'+module.$name+'"');
    if (rtl.debug_load_units) rtl.debug('loadimpl: load uses of "'+module.$name+'"');
    module.$state=rtl.m_loading_impl;
    // load interfaces of implementation useslist
    rtl.loaduseslist(module,module.$impluseslist,rtl.loadintf);
    // load implementation of interfaces useslist
    rtl.loaduseslist(module,module.$intfuseslist,rtl.loadimpl);
    // load implementation of implementation useslist
    rtl.loaduseslist(module,module.$impluseslist,rtl.loadimpl);
    // Note: At this point all interfaces used by this unit are loaded. If
    //   there are implementation uses cycles some used units might not yet be
    //   initialized. This is by design.
    // run implementation
    if (rtl.debug_load_units) rtl.debug('loadimpl: run impl of "'+module.$name+'"');
    if (rtl.isFunction(module.$implcode)) module.$implcode(module.$impluseslist);
    // run initialization
    if (rtl.debug_load_units) rtl.debug('loadimpl: run init of "'+module.$name+'"');
    module.$state=rtl.m_initializing;
    if (rtl.isFunction(module.$init)) module.$init();
    // unit initialized
    module.$state=rtl.m_initialized;
  },

  createCallback: function(scope, fn){
    var cb;
    if (typeof(fn)==='string'){
      if (!scope.hasOwnProperty('$events')) scope.$events = {};
      cb = scope.$events[fn];
      if (cb) return cb;
      scope.$events[fn] = cb = function(){
        return scope[fn].apply(scope,arguments);
      };
    } else {
      cb = function(){
        return fn.apply(scope,arguments);
      };
    };
    cb.scope = scope;
    cb.fn = fn;
    return cb;
  },

  createSafeCallback: function(scope, fn){
    var cb;
    if (typeof(fn)==='string'){
      if (!scope[fn]) return null;
      if (!scope.hasOwnProperty('$events')) scope.$events = {};
      cb = scope.$events[fn];
      if (cb) return cb;
      scope.$events[fn] = cb = function(){
        try{
          return scope[fn].apply(scope,arguments);
        } catch (err) {
          if (!rtl.handleUncaughtException(err)) throw err;
        }
      };
    } else if(!fn) {
      return null;
    } else {
      cb = function(){
        try{
          return fn.apply(scope,arguments);
        } catch (err) {
          if (!rtl.handleUncaughtException(err)) throw err;
        }
      };
    };
    cb.scope = scope;
    cb.fn = fn;
    return cb;
  },

  eqCallback: function(a,b){
    // can be a function or a function wrapper
    if (a===b){
      return true;
    } else {
      return (a!=null) && (b!=null) && (a.fn) && (a.scope===b.scope) && (a.fn===b.fn);
    }
  },

  initStruct: function(c,parent,name){
    if ((parent.$module) && (parent.$module.$impl===parent)) parent=parent.$module;
    c.$parent = parent;
    if (rtl.isModule(parent)){
      c.$module = parent;
      c.$name = name;
    } else {
      c.$module = parent.$module;
      c.$name = parent.$name+'.'+name;
    };
    return parent;
  },

  initClass: function(c,parent,name,initfn,rttiname){
    parent[name] = c;
    c.$class = c; // Note: o.$class === Object.getPrototypeOf(o)
    c.$classname = rttiname?rttiname:name;
    parent = rtl.initStruct(c,parent,name);
    c.$fullname = parent.$name+'.'+name;
    // rtti
    if (rtl.debug_rtti) rtl.debug('initClass '+c.$fullname);
    var t = c.$module.$rtti.$Class(c.$classname,{ "class": c });
    c.$rtti = t;
    if (rtl.isObject(c.$ancestor)) t.ancestor = c.$ancestor.$rtti;
    if (!t.ancestor) t.ancestor = null;
    // init members
    initfn.call(c);
  },

  createClass: function(parent,name,ancestor,initfn,rttiname){
    // create a normal class,
    // ancestor must be null or a normal class,
    // the root ancestor can be an external class
    var c = null;
    if (ancestor != null){
      c = Object.create(ancestor);
      c.$ancestor = ancestor;
      // Note:
      // if root is an "object" then c.$ancestor === Object.getPrototypeOf(c)
      // if root is a "function" then c.$ancestor === c.__proto__, Object.getPrototypeOf(c) returns the root
    } else {
      c = { $ancestor: null };
      c.$create = function(fn,args){
        if (args == undefined) args = [];
        var o = Object.create(this);
        o.$init();
        try{
          if (typeof(fn)==="string"){
            o[fn].apply(o,args);
          } else {
            fn.apply(o,args);
          };
          o.AfterConstruction();
        } catch($e){
          // do not call BeforeDestruction
          if (o.Destroy) o.Destroy();
          o.$final();
          throw $e;
        }
        return o;
      };
      c.$destroy = function(fnname){
        this.BeforeDestruction();
        if (this[fnname]) this[fnname]();
        this.$final();
      };
    };
    rtl.initClass(c,parent,name,initfn,rttiname);
  },

  createClassExt: function(parent,name,ancestor,newinstancefnname,initfn,rttiname){
    // Create a class using an external ancestor.
    // If newinstancefnname is given, use that function to create the new object.
    // If exist call BeforeDestruction and AfterConstruction.
    var isFunc = rtl.isFunction(ancestor);
    var c = null;
    if (isFunc){
      // create pascal class descendent from JS function
      c = Object.create(ancestor.prototype);
      c.$ancestorfunc = ancestor;
      c.$ancestor = null; // no pascal ancestor
    } else if (ancestor.$func){
      // create pascal class descendent from a pascal class descendent of a JS function
      isFunc = true;
      c = Object.create(ancestor);
      c.$ancestor = ancestor;
    } else {
      c = Object.create(ancestor);
      c.$ancestor = null; // no pascal ancestor
    }
    c.$create = function(fn,args){
      if (args == undefined) args = [];
      var o = null;
      if (newinstancefnname.length>0){
        o = this[newinstancefnname](fn,args);
      } else if(isFunc) {
        o = new this.$func(args);
      } else {
        o = Object.create(c);
      }
      if (o.$init) o.$init();
      try{
        if (typeof(fn)==="string"){
          this[fn].apply(o,args);
        } else {
          fn.apply(o,args);
        };
        if (o.AfterConstruction) o.AfterConstruction();
      } catch($e){
        // do not call BeforeDestruction
        if (o.Destroy) o.Destroy();
        if (o.$final) o.$final();
        throw $e;
      }
      return o;
    };
    c.$destroy = function(fnname){
      if (this.BeforeDestruction) this.BeforeDestruction();
      if (this[fnname]) this[fnname]();
      if (this.$final) this.$final();
    };
    rtl.initClass(c,parent,name,initfn,rttiname);
    if (isFunc){
      function f(){}
      f.prototype = c;
      c.$func = f;
    }
  },

  createHelper: function(parent,name,ancestor,initfn,rttiname){
    // create a helper,
    // ancestor must be null or a helper,
    var c = null;
    if (ancestor != null){
      c = Object.create(ancestor);
      c.$ancestor = ancestor;
      // c.$ancestor === Object.getPrototypeOf(c)
    } else {
      c = { $ancestor: null };
    };
    parent[name] = c;
    c.$class = c; // Note: o.$class === Object.getPrototypeOf(o)
    c.$classname = rttiname?rttiname:name;
    parent = rtl.initStruct(c,parent,name);
    c.$fullname = parent.$name+'.'+name;
    // rtti
    var t = c.$module.$rtti.$Helper(c.$classname,{ "helper": c });
    c.$rtti = t;
    if (rtl.isObject(ancestor)) t.ancestor = ancestor.$rtti;
    if (!t.ancestor) t.ancestor = null;
    // init members
    initfn.call(c);
  },

  tObjectDestroy: "Destroy",

  free: function(obj,name){
    if (obj[name]==null) return null;
    obj[name].$destroy(rtl.tObjectDestroy);
    obj[name]=null;
  },

  freeLoc: function(obj){
    if (obj==null) return null;
    obj.$destroy(rtl.tObjectDestroy);
    return null;
  },

  hideProp: function(o,p,v){
    Object.defineProperty(o,p, {
      enumerable: false,
      configurable: true,
      writable: true
    });
    if(arguments.length>2){ o[p]=v; }
  },

  recNewT: function(parent,name,initfn,full){
    // create new record type
    var t = {};
    if (parent) parent[name] = t;
    var h = rtl.hideProp;
    if (full){
      rtl.initStruct(t,parent,name);
      t.$record = t;
      h(t,'$record');
      h(t,'$name');
      h(t,'$parent');
      h(t,'$module');
      h(t,'$initSpec');
    }
    initfn.call(t);
    if (!t.$new){
      t.$new = function(){ return Object.create(t); };
    }
    t.$clone = function(r){ return t.$new().$assign(r); };
    h(t,'$new');
    h(t,'$clone');
    h(t,'$eq');
    h(t,'$assign');
    return t;
  },

  is: function(instance,type){
    return type.isPrototypeOf(instance) || (instance===type);
  },

  isExt: function(instance,type,mode){
    // mode===1 means instance must be a Pascal class instance
    // mode===2 means instance must be a Pascal class
    // Notes:
    // isPrototypeOf and instanceof return false on equal
    // isPrototypeOf does not work for Date.isPrototypeOf(new Date())
    //   so if isPrototypeOf is false test with instanceof
    // instanceof needs a function on right side
    if (instance == null) return false; // Note: ==null checks for undefined too
    if ((typeof(type) !== 'object') && (typeof(type) !== 'function')) return false;
    if (instance === type){
      if (mode===1) return false;
      if (mode===2) return rtl.isPasClass(instance);
      return true;
    }
    if (type.isPrototypeOf && type.isPrototypeOf(instance)){
      if (mode===1) return rtl.isPasClassInstance(instance);
      if (mode===2) return rtl.isPasClass(instance);
      return true;
    }
    if ((typeof type == 'function') && (instance instanceof type)) return true;
    return false;
  },

  Exception: null,
  EInvalidCast: null,
  EAbstractError: null,
  ERangeError: null,
  EIntOverflow: null,
  EPropWriteOnly: null,

  raiseE: function(typename){
    var t = rtl[typename];
    if (t==null){
      var mod = pas.SysUtils;
      if (!mod) mod = pas.sysutils;
      if (!mod) mod = pas["System.SysUtils"];
      if (mod){
        t = mod[typename];
        if (!t) t = mod[typename.toLowerCase()];
        if (!t) t = mod['Exception'];
        if (!t) t = mod['exception'];
      }
      if (t) rtl[typename]=t;
    }
    if (t) {
      
      if (t.Create){
        var e = t.$create("Create");
      } else if (t.create) {
        var e = t.$create("create");
      }
      if (e) {
        e.FJSError = new Error;
        throw e ;
      }
    }
    if (typename === "EInvalidCast") throw new Error("invalid type cast");
    if (typename === "EAbstractError") throw new Error("Abstract method called");
    if (typename === "ERangeError") throw new Error("range error");
    throw typename;
  },

  as: function(instance,type){
    if((instance === null) || rtl.is(instance,type)) return instance;
    rtl.raiseE("EInvalidCast");
  },

  asExt: function(instance,type,mode){
    if((instance === null) || rtl.isExt(instance,type,mode)) return instance;
    rtl.raiseE("EInvalidCast");
  },

  createInterface: function(module, name, guid, fnnames, ancestor, initfn, rttiname){
    //console.log('createInterface name="'+name+'" guid="'+guid+'" names='+fnnames);
    var i = ancestor?Object.create(ancestor):{};
    module[name] = i;
    i.$module = module;
    i.$name = rttiname?rttiname:name;
    i.$fullname = module.$name+'.'+i.$name;
    i.$guid = guid;
    i.$guidr = null;
    i.$names = fnnames?fnnames:[];
    if (rtl.isFunction(initfn)){
      // rtti
      if (rtl.debug_rtti) rtl.debug('createInterface '+i.$fullname);
      var t = i.$module.$rtti.$Interface(i.$name,{ "interface": i, module: module });
      i.$rtti = t;
      if (ancestor) t.ancestor = ancestor.$rtti;
      if (!t.ancestor) t.ancestor = null;
      initfn.call(i);
    }
    return i;
  },

  strToGUIDR: function(s,g){
    var p = 0;
    function n(l){
      var h = s.substr(p,l);
      p+=l;
      return parseInt(h,16);
    }
    p+=1; // skip {
    g.D1 = n(8);
    p+=1; // skip -
    g.D2 = n(4);
    p+=1; // skip -
    g.D3 = n(4);
    p+=1; // skip -
    if (!g.D4) g.D4=[];
    g.D4[0] = n(2);
    g.D4[1] = n(2);
    p+=1; // skip -
    for(var i=2; i<8; i++) g.D4[i] = n(2);
    return g;
  },

  guidrToStr: function(g){
    if (g.$intf) return g.$intf.$guid;
    var h = rtl.hexStr;
    var s='{'+h(g.D1,8)+'-'+h(g.D2,4)+'-'+h(g.D3,4)+'-'+h(g.D4[0],2)+h(g.D4[1],2)+'-';
    for (var i=2; i<8; i++) s+=h(g.D4[i],2);
    s+='}';
    return s;
  },

  createTGUID: function(guid){
    var TGuid = (pas.System)?pas.System.TGuid:pas.system.tguid;
    var g = rtl.strToGUIDR(guid,TGuid.$new());
    return g;
  },

  getIntfGUIDR: function(intfTypeOrVar){
    if (!intfTypeOrVar) return null;
    if (!intfTypeOrVar.$guidr){
      var g = rtl.createTGUID(intfTypeOrVar.$guid);
      if (!intfTypeOrVar.hasOwnProperty('$guid')) intfTypeOrVar = Object.getPrototypeOf(intfTypeOrVar);
      g.$intf = intfTypeOrVar;
      intfTypeOrVar.$guidr = g;
    }
    return intfTypeOrVar.$guidr;
  },

  addIntf: function (aclass, intf, map){
    function jmp(fn){
      if (typeof(fn)==="function"){
        return function(){ return fn.apply(this.$o,arguments); };
      } else {
        return function(){ rtl.raiseE('EAbstractError'); };
      }
    }
    if(!map) map = {};
    var t = intf;
    var item = Object.create(t);
    if (!aclass.hasOwnProperty('$intfmaps')) aclass.$intfmaps = {};
    aclass.$intfmaps[intf.$guid] = item;
    do{
      var names = t.$names;
      if (!names) break;
      for (var i=0; i<names.length; i++){
        var intfname = names[i];
        var fnname = map[intfname];
        if (!fnname) fnname = intfname;
        //console.log('addIntf: intftype='+t.$name+' index='+i+' intfname="'+intfname+'" fnname="'+fnname+'" old='+typeof(item[intfname]));
        item[intfname] = jmp(aclass[fnname]);
      }
      t = Object.getPrototypeOf(t);
    }while(t!=null);
  },

  getIntfG: function (obj, guid, query){
    if (!obj) return null;
    //console.log('getIntfG: obj='+obj.$classname+' guid='+guid+' query='+query);
    // search
    var maps = obj.$intfmaps;
    if (!maps) return null;
    var item = maps[guid];
    if (!item) return null;
    // check delegation
    //console.log('getIntfG: obj='+obj.$classname+' guid='+guid+' query='+query+' item='+typeof(item));
    if (typeof item === 'function') return item.call(obj); // delegate. Note: COM contains _AddRef
    // check cache
    var intf = null;
    if (obj.$interfaces){
      intf = obj.$interfaces[guid];
      //console.log('getIntfG: obj='+obj.$classname+' guid='+guid+' cache='+typeof(intf));
    }
    if (!intf){ // intf can be undefined!
      intf = Object.create(item);
      intf.$o = obj;
      if (!obj.$interfaces) obj.$interfaces = {};
      obj.$interfaces[guid] = intf;
    }
    if (typeof(query)==='object'){
      // called by queryIntfT
      var o = null;
      if (intf.QueryInterface(rtl.getIntfGUIDR(query),
          {get:function(){ return o; }, set:function(v){ o=v; }}) === 0){
        return o;
      } else {
        return null;
      }
    } else if(query===2){
      // called by TObject.GetInterfaceByStr
      if (intf.$kind === 'com') intf._AddRef();
    }
    return intf;
  },

  getIntfT: function(obj,intftype){
    return rtl.getIntfG(obj,intftype.$guid);
  },

  queryIntfT: function(obj,intftype){
    return rtl.getIntfG(obj,intftype.$guid,intftype);
  },

  queryIntfIsT: function(obj,intftype){
    var i = rtl.getIntfG(obj,intftype.$guid);
    if (!i) return false;
    if (i.$kind === 'com') i._Release();
    return true;
  },

  asIntfT: function (obj,intftype){
    var i = rtl.getIntfG(obj,intftype.$guid);
    if (i!==null) return i;
    rtl.raiseEInvalidCast();
  },

  intfIsIntfT: function(intf,intftype){
    return (intf!==null) && rtl.queryIntfIsT(intf.$o,intftype);
  },

  intfAsIntfT: function (intf,intftype){
    if (!intf) return null;
    var i = rtl.getIntfG(intf.$o,intftype.$guid);
    if (i) return i;
    rtl.raiseEInvalidCast();
  },

  intfIsClass: function(intf,classtype){
    return (intf!=null) && (rtl.is(intf.$o,classtype));
  },

  intfAsClass: function(intf,classtype){
    if (intf==null) return null;
    return rtl.as(intf.$o,classtype);
  },

  intfToClass: function(intf,classtype){
    if ((intf!==null) && rtl.is(intf.$o,classtype)) return intf.$o;
    return null;
  },

  // interface reference counting
  intfRefs: { // base object for temporary interface variables
    ref: function(id,intf){
      // called for temporary interface references needing delayed release
      var old = this[id];
      //console.log('rtl.intfRefs.ref: id='+id+' old="'+(old?old.$name:'null')+'" intf="'+(intf?intf.$name:'null')+' $o='+(intf?intf.$o:'null'));
      if (old){
        // called again, e.g. in a loop
        delete this[id];
        old._Release(); // may fail
      }
      if(intf) {
        this[id]=intf;
      }
      return intf;
    },
    free: function(){
      //console.log('rtl.intfRefs.free...');
      for (var id in this){
        if (this.hasOwnProperty(id)){
          var intf = this[id];
          if (intf){
            //console.log('rtl.intfRefs.free: id='+id+' '+intf.$name+' $o='+intf.$o.$classname);
            intf._Release();
          }
        }
      }
    }
  },

  createIntfRefs: function(){
    //console.log('rtl.createIntfRefs');
    return Object.create(rtl.intfRefs);
  },

  setIntfP: function(path,name,value,skipAddRef){
    var old = path[name];
    //console.log('rtl.setIntfP path='+path+' name='+name+' old="'+(old?old.$name:'null')+'" value="'+(value?value.$name:'null')+'"');
    if (old === value) return;
    if (old !== null){
      path[name]=null;
      old._Release();
    }
    if (value !== null){
      if (!skipAddRef) value._AddRef();
      path[name]=value;
    }
  },

  setIntfL: function(old,value,skipAddRef){
    //console.log('rtl.setIntfL old="'+(old?old.$name:'null')+'" value="'+(value?value.$name:'null')+'"');
    if (old !== value){
      if (value!==null){
        if (!skipAddRef) value._AddRef();
      }
      if (old!==null){
        old._Release();  // Release after AddRef, to avoid double Release if Release creates an exception
      }
    } else if (skipAddRef){
      if (old!==null){
        old._Release();  // value has an AddRef
      }
    }
    return value;
  },

  _AddRef: function(intf){
    //if (intf) console.log('rtl._AddRef intf="'+(intf?intf.$name:'null')+'"');
    if (intf) intf._AddRef();
    return intf;
  },

  _Release: function(intf){
    //if (intf) console.log('rtl._Release intf="'+(intf?intf.$name:'null')+'"');
    if (intf) intf._Release();
    return intf;
  },

  trunc: function(a){
    return a<0 ? Math.ceil(a) : Math.floor(a);
  },

  checkMethodCall: function(obj,type){
    if (rtl.isObject(obj) && rtl.is(obj,type)) return;
    rtl.raiseE("EInvalidCast");
  },

  oc: function(i){
    // overflow check integer
    if ((Math.floor(i)===i) && (i>=-0x1fffffffffffff) && (i<=0x1fffffffffffff)) return i;
    rtl.raiseE('EIntOverflow');
  },

  rc: function(i,minval,maxval){
    // range check integer
    if ((Math.floor(i)===i) && (i>=minval) && (i<=maxval)) return i;
    rtl.raiseE('ERangeError');
  },

  rcc: function(c,minval,maxval){
    // range check char
    if ((typeof(c)==='string') && (c.length===1)){
      var i = c.charCodeAt(0);
      if ((i>=minval) && (i<=maxval)) return c;
    }
    rtl.raiseE('ERangeError');
  },

  rcSetCharAt: function(s,index,c){
    // range check setCharAt
    if ((typeof(s)!=='string') || (index<0) || (index>=s.length)) rtl.raiseE('ERangeError');
    return rtl.setCharAt(s,index,c);
  },

  rcCharAt: function(s,index){
    // range check charAt
    if ((typeof(s)!=='string') || (index<0) || (index>=s.length)) rtl.raiseE('ERangeError');
    return s.charAt(index);
  },

  rcArrR: function(arr,index){
    // range check read array
    if (Array.isArray(arr) && (typeof(index)==='number') && (index>=0) && (index<arr.length)){
      if (arguments.length>2){
        // arr,index1,index2,...
        arr=arr[index];
        for (var i=2; i<arguments.length; i++) arr=rtl.rcArrR(arr,arguments[i]);
        return arr;
      }
      return arr[index];
    }
    rtl.raiseE('ERangeError');
  },

  rcArrW: function(arr,index,value){
    // range check write array
    // arr,index1,index2,...,value
    for (var i=3; i<arguments.length; i++){
      arr=rtl.rcArrR(arr,index);
      index=arguments[i-1];
      value=arguments[i];
    }
    if (Array.isArray(arr) && (typeof(index)==='number') && (index>=0) && (index<arr.length)){
      return arr[index]=value;
    }
    rtl.raiseE('ERangeError');
  },

  length: function(arr){
    return (arr == null) ? 0 : arr.length;
  },

  arrayRef: function(a){
    if (a!=null) rtl.hideProp(a,'$pas2jsrefcnt',2);
    return a;
  },

  arrayManaged: function(refCnt,mode,a){
    // mode: 0: don't touch elements, 1: null elements, 2: _AddRef elements
    if(!a) a = [];
    a.$pas2jsrefcnt = refCnt?refCnt:0;
    a._AddRef = function(){
      this.$pas2jsrefcnt++;
    };
    a._Release = function(){
      this.$pas2jsrefcnt--;
      if (this.$pas2jsrefcnt==0){
        for (var i=0; i<this.length; i++){
          rtl.setIntfP(this,i,null);
        }
      }
    };
    if (mode>0){
      for (var i=0; i<a.length; i++){
        if (mode === 2){
          rtl._AddRef(a[i]);
        } else {
          a[i]=null;
        }
      }
    }
    return a;
  },

  arraySetLength: function(arr,defaultvalue,newlength){
    var stack = [];
    var s = 9999;
    for (var i=2; i<arguments.length; i++){
      var j = arguments[i];
      if (j==='s'){ s = i-2; }
      else {
        stack.push({ dim:j+0, a:null, i:0, src:null });
      }
    }
    var dimmax = stack.length-1;
    var depth = 0;
    var newlen = 0;
    var item = null;
    var a = null;
    var src = arr;
    var srclen = 0, oldlen = 0;
    var type = 0;
    var managed = false;
    if (rtl.isArray(defaultvalue)){
      // array of dyn array
      type = 1;
    } else if (rtl.isObject(defaultvalue)) {
      if (rtl.isTRecord(defaultvalue)){
        // array of record
        type = 2;
      } else {
        // array of set
        type = 3;
      }
    } else if (defaultvalue == 'R'){
      // array of COM interface
      type = 4;
      managed = true;
    }

    do{
      if (depth>0){
        item = stack[depth-1];
        src = (item.src && item.src.length>item.i) ? item.src[item.i] : null;
      }
      if (!src){
        // init array
        managed ? a=rtl.arrayManaged(1) : a=[];
        srclen = 0;
        oldlen = 0;
      } else if (src.$pas2jsrefcnt>1 || depth>=s){
        // clone
        if (managed){
          a = rtl.arrayManaged(1);
          src.$pas2jsrefcnt--;
        } else {
          a = [];
        }
        srclen = src.length;
        oldlen = srclen;
      } else {
        // keep old
        a = src;
        srclen = 0;
        oldlen = a.length;
      }
      newlen = stack[depth].dim;
      if (managed){
        if (a.length>=newlen){
          // shrink -> release elements
          for (var i=a.length-1; i>=newlen; i--){
            rtl.setIntfP(a,i,null);
          }
          a.length = newlen;
        } else {
          // enlarge -> null elements
          var l = a.length;
          a.length = newlen;
          for (var i=l; i<newlen; i++){
            a[i]=null;
          }
          oldlen = newlen;
        }
      } else {
        a.length = newlen;
      }
      if (depth>0){
        item.a[item.i]=a;
        item.i++;
        if ((newlen===0) && (item.i<item.a.length)) continue;
      }
      if (newlen>0){
        if (depth<dimmax){
          item = stack[depth];
          item.a = a;
          item.i = 0;
          item.src = src;
          depth++;
          continue;
        } else {
          if (srclen>newlen) srclen=newlen;
          if (type == 0){
            // array of simple value
            for (var i=0; i<srclen; i++) a[i]=src[i];
            for (var i=oldlen; i<newlen; i++) a[i]=defaultvalue;
          } else if (type == 1){
            // array of dyn array
            for (var i=0; i<srclen; i++) a[i]=src[i];
            for (var i=oldlen; i<newlen; i++) a[i]=[];
          } else if (type == 2) {
            // array of record
            for (var i=0; i<srclen; i++) a[i]=defaultvalue.$clone(src[i]);
            for (var i=oldlen; i<newlen; i++) a[i]=defaultvalue.$new();
          } else if (type == 3) {
            // array of set
            for (var i=0; i<srclen; i++) a[i]=rtl.refSet(src[i]);
            for (var i=oldlen; i<newlen; i++) a[i]={};
          } else if (type == 4){
            // array of interface
            for (var i=0; i<srclen; i++) rtl.setIntfP(a,i,src[i]);
            for (var i=oldlen; i<newlen; i++) a[i]=null;
          }
        }
      }
      // backtrack
      while ((depth>0) && (stack[depth-1].i>=stack[depth-1].dim)){
        depth--;
      };
      if (depth===0){
        return dimmax===0 ? a : stack[0].a;
      }
    }while (true);
  },

  arrayEq: function(a,b){
    if (a===null) return b===null;
    if (b===null) return false;
    if (a.length!==b.length) return false;
    for (var i=0; i<a.length; i++) if (a[i]!==b[i]) return false;
    return true;
  },

  arrayClone: function(type,src,srcpos,endpos,dst,dstpos){
    // type: 0 for references or simple values
    // src must not be null
    // dst at dstpos must not contain managed old values
    // This function does not range check.
    if(type === 'refSet') {
      for (; srcpos<endpos; srcpos++) dst[dstpos++] = rtl.refSet(src[srcpos]); // ref set
    } else if (type === 'slice'){
      for (; srcpos<endpos; srcpos++) dst[dstpos++] = src[srcpos].slice(0); // clone static array of simple types
    } else if (typeof(type)==='function'){
      for (; srcpos<endpos; srcpos++) dst[dstpos++] = type(src[srcpos]); // clone function
    } else if (rtl.isTRecord(type)){
      for (; srcpos<endpos; srcpos++) dst[dstpos++] = type.$clone(src[srcpos]); // clone record
    } else if (type === 'R'){
      // clone managed instance
      for (; srcpos<endpos; srcpos++){
        dst[dstpos++]=rtl._AddRef(src[srcpos]);
      }
    } else {
      for (; srcpos<endpos; srcpos++) dst[dstpos++] = src[srcpos]; // reference
    };
  },

  arrayConcat: function(type){
    // type: see rtl.arrayClone
    // returns refCnt=1
    var a = [];
    var l = 0;
    for (var i=1; i<arguments.length; i++){
      var src = arguments[i];
      if (src !== null) l+=src.length;
    };
    a.length = l;
    if (type === 'R'){
      rtl.arrayManaged(1,1,a);
    }
    l=0;
    for (var i=1; i<arguments.length; i++){
      var src = arguments[i];
      if (src === null) continue;
      rtl.arrayClone(type,src,0,src.length,a,l);
      l+=src.length;
    };
    return a;
  },

  arrayConcatN: function(){
    var a = null;
    for (var i=0; i<arguments.length; i++){
      var src = arguments[i];
      if (src === null) continue;
      if (a===null){
        a=rtl.arrayRef(src); // Note: concat(arr) does not clone
      } else if (a.$pas2jsrefcnt>1){
        a=a.concat(src); // clone a and append src
      } else {
        for (var i=0; i<src.length; i++){
          a.push(src[i]);
        }
      }
    };
    return a;
  },

  arrayPush: function(type,a){
    if(a===null){
      a=(type==='R') ? rtl.arrayManaged(1) : [];
    } else if (a.$pas2jsrefcnt>1){
      a=rtl.arrayCopy(type,a,0,a.length);
    }
    rtl.arrayClone(type,arguments,2,arguments.length,a,a.length);
    return a;
  },

  arrayPushN: function(a){
    if(a===null){
      a=[];
    } else if (a.$pas2jsrefcnt>1){
      a=a.concat();
    }
    for (var i=1; i<arguments.length; i++){
      a.push(arguments[i]);
    }
    return a;
  },

  arrayCopy: function(type, srcarray, index, count){
    // type: see rtl.arrayClone
    // if count is missing, use srcarray.length
    if (srcarray === null) return (type === 'R') ? null : [];
    if (count === undefined) count=srcarray.length;
    if (index < 0){
      count+=index;
      index = 0;
    }
    var end = index+count;
    if (end>srcarray.length) end = srcarray.length;
    if (index>=end) return (type === 'R') ? null : [];
    if (type===0){
      return srcarray.slice(index,end);
    } else {
      var a = [];
      a.length = end-index;
      if (type === 'R'){
        rtl.arrayManaged(1,1,a);
      }
      rtl.arrayClone(type,srcarray,index,end,a,0);
      return a;
    }
  },

  arrayInsert: function(item, a, index, type){
    var m = (type === 'R');
    if (m) rtl._AddRef(item);
    if (a){
      if (a.$pas2jsrefcnt>1){
        if (m){
          // clone
          a.$pas2jsrefcnt--;
          a=rtl.arrayManaged(1,2,a.concat());
        } else {
          a=a.concat();
        }
      }
      a.splice(index,0,item);
      return a;
    } else {
      a = [item];
      if (m) a=rtl.arrayManaged(1,0,a);
      return a;
    }
  },

  arrayDeleteR: function(a, index, count){
    if (a===null || index<0 || index>=a.length || count<=0) return a;
    if (index+count>a.length) count=a.length-index;
    if (a.$pas2jsrefcnt>1){
      // clone
      a.$pas2jsrefcnt--;
      a=rtl.arrayManaged(1,2,a.concat());
    }
    for (var i=0; i<count; i++) rtl.setIntfP(a,index+i,null);
    a.splice(index,count);
    return a;
  },

  setCharAt: function(s,index,c){
    return s.substr(0,index)+c+s.substr(index+1);
  },

  getResStr: function(mod,name){
    var rs = mod.$resourcestrings[name];
    return rs.current?rs.current:rs.org;
  },

  createSet: function(){
    var s = {};
    for (var i=0; i<arguments.length; i++){
      if (arguments[i]!=null){
        s[arguments[i]]=true;
      } else {
        var first=arguments[i+=1];
        var last=arguments[i+=1];
        for(var j=first; j<=last; j++) s[j]=true;
      }
    }
    return s;
  },

  cloneSet: function(s){
    var r = {};
    for (var key in s) r[key]=true;
    return r;
  },

  refSet: function(s){
    rtl.hideProp(s,'$shared',true);
    return s;
  },

  includeSet: function(s,enumvalue){
    if (s.$shared) s = rtl.cloneSet(s);
    s[enumvalue] = true;
    return s;
  },

  excludeSet: function(s,enumvalue){
    if (s.$shared) s = rtl.cloneSet(s);
    delete s[enumvalue];
    return s;
  },

  diffSet: function(s,t){
    var r = {};
    for (var key in s) if (!t[key]) r[key]=true;
    return r;
  },

  unionSet: function(s,t){
    var r = {};
    for (var key in s) r[key]=true;
    for (var key in t) r[key]=true;
    return r;
  },

  intersectSet: function(s,t){
    var r = {};
    for (var key in s) if (t[key]) r[key]=true;
    return r;
  },

  symDiffSet: function(s,t){
    var r = {};
    for (var key in s) if (!t[key]) r[key]=true;
    for (var key in t) if (!s[key]) r[key]=true;
    return r;
  },

  eqSet: function(s,t){
    for (var key in s) if (!t[key]) return false;
    for (var key in t) if (!s[key]) return false;
    return true;
  },

  neSet: function(s,t){
    return !rtl.eqSet(s,t);
  },

  leSet: function(s,t){
    for (var key in s) if (!t[key]) return false;
    return true;
  },

  geSet: function(s,t){
    for (var key in t) if (!s[key]) return false;
    return true;
  },

  strSetLength: function(s,newlen){
    var oldlen = s.length;
    if (oldlen > newlen){
      return s.substring(0,newlen);
    } else if (s.repeat){
      // Note: repeat needs ECMAScript6!
      return s+' '.repeat(newlen-oldlen);
    } else {
       while (oldlen<newlen){
         s+=' ';
         oldlen++;
       };
       return s;
    }
  },

  spaceLeft: function(s,width){
    var l=s.length;
    if (l>=width) return s;
    if (s.repeat){
      // Note: repeat needs ECMAScript6!
      return ' '.repeat(width-l) + s;
    } else {
      while (l<width){
        s=' '+s;
        l++;
      };
      return s;
    };
  },

  floatToStr: function(d,w,p){
    // input 1-3 arguments: double, width, precision
    if (arguments.length>2){
      return rtl.spaceLeft(d.toFixed(p),w);
    } else {
	  // exponent width
	  var pad = "";
	  var ad = Math.abs(d);
	  if (((ad>1) && (ad<1.0e+10)) ||  ((ad>1.e-10) && (ad<1))) {
		pad='00';
	  } else if ((ad>1) && (ad<1.0e+100) || (ad<1.e-10)) {
		pad='0';
      }  	
	  if (arguments.length<2) {
	    w=24;		
      } else if (w<9) {
		w=9;
      }		  
      var p = w-8;
      var s=(d>0 ? " " : "" ) + d.toExponential(p);
      s=s.replace(/e(.)/,'E$1'+pad);
      return rtl.spaceLeft(s,w);
    }
  },

  valEnum: function(s, enumType, setCodeFn){
    s = s.toLowerCase();
    for (var key in enumType){
      if((typeof(key)==='string') && (key.toLowerCase()===s)){
        setCodeFn(0);
        return enumType[key];
      }
    }
    setCodeFn(1);
    return 0;
  },

  lw: function(l){
    // fix longword bitwise operation
    return l<0?l+0x100000000:l;
  },

  and: function(a,b){
    var hi = 0x80000000;
    var low = 0x7fffffff;
    var h = (a / hi) & (b / hi);
    var l = (a & low) & (b & low);
    return h*hi + l;
  },

  or: function(a,b){
    var hi = 0x80000000;
    var low = 0x7fffffff;
    var h = (a / hi) | (b / hi);
    var l = (a & low) | (b & low);
    return h*hi + l;
  },

  xor: function(a,b){
    var hi = 0x80000000;
    var low = 0x7fffffff;
    var h = (a / hi) ^ (b / hi);
    var l = (a & low) ^ (b & low);
    return h*hi + l;
  },

  shr: function(a,b){
    if (a<0) a += rtl.hiInt;
    if (a<0x80000000) return a >> b;
    if (b<=0) return a;
    if (b>54) return 0;
    return Math.floor(a / Math.pow(2,b));
  },

  shl: function(a,b){
    if (a<0) a += rtl.hiInt;
    if (b<=0) return a;
    if (b>54) return 0;
    var r = a * Math.pow(2,b);
    if (r <= rtl.hiInt) return r;
    return r % rtl.hiInt;
  },

  initRTTI: function(){
    if (rtl.debug_rtti) rtl.debug('initRTTI');

    // base types
    rtl.tTypeInfo = { name: "tTypeInfo", kind: 0, $module: null, attr: null };
    function newBaseTI(name,kind,ancestor){
      if (!ancestor) ancestor = rtl.tTypeInfo;
      if (rtl.debug_rtti) rtl.debug('initRTTI.newBaseTI "'+name+'" '+kind+' ("'+ancestor.name+'")');
      var t = Object.create(ancestor);
      t.name = name;
      t.kind = kind;
      rtl[name] = t;
      return t;
    };
    function newBaseInt(name,minvalue,maxvalue,ordtype){
      var t = newBaseTI(name,1 /* tkInteger */,rtl.tTypeInfoInteger);
      t.minvalue = minvalue;
      t.maxvalue = maxvalue;
      t.ordtype = ordtype;
      return t;
    };
    newBaseTI("tTypeInfoInteger",1 /* tkInteger */);
    newBaseInt("shortint",-0x80,0x7f,0);
    newBaseInt("byte",0,0xff,1);
    newBaseInt("smallint",-0x8000,0x7fff,2);
    newBaseInt("word",0,0xffff,3);
    newBaseInt("longint",-0x80000000,0x7fffffff,4);
    newBaseInt("longword",0,0xffffffff,5);
    newBaseInt("nativeint",-0x10000000000000,0xfffffffffffff,6);
    newBaseInt("nativeuint",0,0xfffffffffffff,7);
    newBaseInt("char",0,65535,3 /* word */).kind=2 /* tkChar */;
    newBaseTI("string",3 /* tkString */);
    newBaseTI("tTypeInfoEnum",4 /* tkEnumeration */,rtl.tTypeInfoInteger);
    newBaseTI("tTypeInfoSet",5 /* tkSet */);
    newBaseTI("double",6 /* tkDouble */);
    newBaseTI("boolean",7 /* tkBool */);
    newBaseTI("tTypeInfoProcVar",8 /* tkProcVar */);
    newBaseTI("tTypeInfoMethodVar",9 /* tkMethod */,rtl.tTypeInfoProcVar);
    newBaseTI("tTypeInfoArray",10 /* tkArray */);
    newBaseTI("tTypeInfoDynArray",11 /* tkDynArray */);
    newBaseTI("tTypeInfoPointer",15 /* tkPointer */);
    var t = newBaseTI("pointer",15 /* tkPointer */,rtl.tTypeInfoPointer);
    t.reftype = null;
    newBaseTI("jsvalue",16 /* tkJSValue */);
    newBaseTI("tTypeInfoRefToProcVar",17 /* tkRefToProcVar */,rtl.tTypeInfoProcVar);

    // member kinds
    rtl.tTypeMember = { attr: null };
    function newMember(name,kind){
      var m = Object.create(rtl.tTypeMember);
      m.name = name;
      m.kind = kind;
      rtl[name] = m;
    };
    newMember("tTypeMemberField",1); // tmkField
    newMember("tTypeMemberMethod",2); // tmkMethod
    newMember("tTypeMemberProperty",3); // tmkProperty

    // base object for storing members: a simple object
    rtl.tTypeMembers = {};

    // tTypeInfoStruct - base object for tTypeInfoClass, tTypeInfoRecord, tTypeInfoInterface
    var tis = newBaseTI("tTypeInfoStruct",0);
    tis.$addMember = function(name,ancestor,vis,options){
      if (rtl.debug_rtti){
        if (!rtl.hasString(name) || (name.charAt()==='$')) throw 'invalid member "'+name+'", this="'+this.name+'"';
        if (!rtl.is(ancestor,rtl.tTypeMember)) throw 'invalid ancestor "'+ancestor+':'+ancestor.name+'", "'+this.name+'.'+name+'"';
        if ((options!=undefined) && (typeof(options)!='object')) throw 'invalid options "'+options+'", "'+this.name+'.'+name+'"';
      };
      var t = Object.create(ancestor);
      t.name = name;
      this.members[name] = t;
      this.names.push(name);
      t.visibility = vis;
      if (rtl.isObject(options)){
        for (var key in options) if (options.hasOwnProperty(key)) t[key] = options[key];
      };
      return t;
    };
    tis.addField = function(name,type,vis,options){
      var t = this.$addMember(name,rtl.tTypeMemberField,vis?vis:2,options);
      if (rtl.debug_rtti){
        if (!rtl.is(type,rtl.tTypeInfo)) throw 'invalid type "'+type+'", "'+this.name+'.'+name+'"';
      };
      t.typeinfo = type;
      this.fields.push(name);
      return t;
    };
    tis.addFields = function(){
      var i=0;
      while(i<arguments.length){
        var name = arguments[i++];
        var type = arguments[i++];
        if ((i<arguments.length) && (typeof(arguments[i])==='object')){
          this.addField(name,type,arguments[i++]);
        } else {
          this.addField(name,type);
        };
      };
    };
    tis.addMethod = function(name,methodkind,params,vis,result,flags,options){
      // optional: vis, result, flags, options
      var t = this.$addMember(name,rtl.tTypeMemberMethod,vis?vis:2,options);
      t.methodkind = methodkind;
      t.procsig = rtl.newTIProcSig(params,result,flags);
      this.methods.push(name);
      return t;
    };
    tis.addProperty = function(name,flags,result,getter,setter,vis,options){
      var t = this.$addMember(name,rtl.tTypeMemberProperty,vis?vis:4,options);
      t.flags = flags;
      t.typeinfo = result;
      t.getter = getter;
      t.setter = setter;
      // Note: in options: params, stored, defaultvalue
      t.params = rtl.isArray(t.params) ? rtl.newTIParams(t.params) : null;
      this.properties.push(name);
      if (!rtl.isString(t.stored)) t.stored = "";
      return t;
    };
    tis.getField = function(index){
      return this.members[this.fields[index]];
    };
    tis.getMethod = function(index){
      return this.members[this.methods[index]];
    };
    tis.getProperty = function(index){
      return this.members[this.properties[index]];
    };

    newBaseTI("tTypeInfoRecord",12 /* tkRecord */,rtl.tTypeInfoStruct);
    newBaseTI("tTypeInfoClass",13 /* tkClass */,rtl.tTypeInfoStruct);
    newBaseTI("tTypeInfoClassRef",14 /* tkClassRef */);
    newBaseTI("tTypeInfoInterface",18 /* tkInterface */,rtl.tTypeInfoStruct);
    newBaseTI("tTypeInfoHelper",19 /* tkHelper */,rtl.tTypeInfoStruct);
    newBaseTI("tTypeInfoExtClass",20 /* tkExtClass */,rtl.tTypeInfoClass);
  },

  tSectionRTTI: {
    $module: null,
    $inherited: function(name,ancestor,o){
      if (rtl.debug_rtti){
        rtl.debug('tSectionRTTI.newTI "'+(this.$module?this.$module.$name:"(no module)")
          +'"."'+name+'" ('+ancestor.name+') '+(o?'init':'forward'));
      };
      var t = this[name];
      if (t){
        if (!t.$forward) throw 'duplicate type "'+name+'"';
        if (!ancestor.isPrototypeOf(t)) throw 'typeinfo ancestor mismatch "'+name+'" ancestor="'+ancestor.name+'" t.name="'+t.name+'"';
      } else {
        t = Object.create(ancestor);
        t.name = name;
        t.$module = this.$module;
        this[name] = t;
      }
      if (o){
        delete t.$forward;
        for (var key in o) if (o.hasOwnProperty(key)) t[key]=o[key];
      } else {
        t.$forward = true;
      }
      return t;
    },
    $Scope: function(name,ancestor,o){
      var t=this.$inherited(name,ancestor,o);
      t.members = {};
      t.names = [];
      t.fields = [];
      t.methods = [];
      t.properties = [];
      return t;
    },
    $TI: function(name,kind,o){ var t=this.$inherited(name,rtl.tTypeInfo,o); t.kind = kind; return t; },
    $Int: function(name,o){ return this.$inherited(name,rtl.tTypeInfoInteger,o); },
    $Enum: function(name,o){ return this.$inherited(name,rtl.tTypeInfoEnum,o); },
    $Set: function(name,o){ return this.$inherited(name,rtl.tTypeInfoSet,o); },
    $StaticArray: function(name,o){ return this.$inherited(name,rtl.tTypeInfoArray,o); },
    $DynArray: function(name,o){ return this.$inherited(name,rtl.tTypeInfoDynArray,o); },
    $ProcVar: function(name,o){ return this.$inherited(name,rtl.tTypeInfoProcVar,o); },
    $RefToProcVar: function(name,o){ return this.$inherited(name,rtl.tTypeInfoRefToProcVar,o); },
    $MethodVar: function(name,o){ return this.$inherited(name,rtl.tTypeInfoMethodVar,o); },
    $Record: function(name,o,typ){ if(typ) o.$record = typ; return this.$Scope(name,rtl.tTypeInfoRecord,o); },
    $Class: function(name,o){ return this.$Scope(name,rtl.tTypeInfoClass,o); },
    $ClassRef: function(name,o){ return this.$inherited(name,rtl.tTypeInfoClassRef,o); },
    $Pointer: function(name,o){ return this.$inherited(name,rtl.tTypeInfoPointer,o); },
    $Interface: function(name,o){ return this.$Scope(name,rtl.tTypeInfoInterface,o); },
    $Helper: function(name,o){ return this.$Scope(name,rtl.tTypeInfoHelper,o); },
    $ExtClass: function(name,o){ return this.$Scope(name,rtl.tTypeInfoExtClass,o); }
  },

  newTIParam: function(param){
    // param is an array, 0=name, 1=type, 2=optional flags
    var t = {
      name: param[0],
      typeinfo: param[1],
      flags: (rtl.isNumber(param[2]) ? param[2] : 0)
    };
    return t;
  },

  newTIParams: function(list){
    // list: optional array of [paramname,typeinfo,optional flags]
    var params = [];
    if (rtl.isArray(list)){
      for (var i=0; i<list.length; i++) params.push(rtl.newTIParam(list[i]));
    };
    return params;
  },

  newTIProcSig: function(params,result,flags){
    var s = {
      params: rtl.newTIParams(params),
      resulttype: result?result:null,
      flags: flags?flags:0
    };
    return s;
  },

  addResource: function(aRes){
    rtl.$res[aRes.name]=aRes;
  },

  getResource: function(aName){
    var res = rtl.$res[aName];
    if (res !== undefined) {
      return res;
    } else {
      return null;
    }
  },

  getResourceList: function(){
    return Object.keys(rtl.$res);
  }
}

rtl.module("System",[],function () {
  "use strict";
  var $mod = this;
  this.MaxLongint = 0x7fffffff;
  this.Maxint = 2147483647;
  rtl.createClass(this,"TObject",null,function () {
    this.$init = function () {
    };
    this.$final = function () {
    };
    this.Create = function () {
      return this;
    };
    this.AfterConstruction = function () {
    };
    this.BeforeDestruction = function () {
    };
  });
  this.Frac = function (A) {
    return A % 1;
  };
  this.Trunc = function (A) {
    if (!Math.trunc) {
      Math.trunc = function(v) {
        v = +v;
        if (!isFinite(v)) return v;
        return (v - v % 1) || (v < 0 ? -0 : v === 0 ? v : 0);
      };
    }
    $mod.Trunc = Math.trunc;
    return Math.trunc(A);
  };
  this.Copy = function (S, Index, Size) {
    if (Index<1) Index = 1;
    return (Size>0) ? S.substring(Index-1,Index+Size-1) : "";
  };
  this.Copy$1 = function (S, Index) {
    if (Index<1) Index = 1;
    return S.substr(Index-1);
  };
  this.Delete = function (S, Index, Size) {
    var h = "";
    if ((Index < 1) || (Index > S.get().length) || (Size <= 0)) return;
    h = S.get();
    S.set($mod.Copy(h,1,Index - 1) + $mod.Copy$1(h,Index + Size));
  };
  this.Pos = function (Search, InString) {
    return InString.indexOf(Search)+1;
  };
  this.upcase = function (c) {
    return c.toUpperCase();
  };
  this.StringOfChar = function (c, l) {
    var Result = "";
    var i = 0;
    if ((l>0) && c.repeat) return c.repeat(l);
    Result = "";
    for (var $l = 1, $end = l; $l <= $end; $l++) {
      i = $l;
      Result = Result + c;
    };
    return Result;
  };
  $mod.$init = function () {
    rtl.exitcode = 0;
  };
});
rtl.module("JS",["System"],function () {
  "use strict";
  var $mod = this;
});
rtl.module("weborworker",["System","JS"],function () {
  "use strict";
  var $mod = this;
});
rtl.module("Web",["System","JS","weborworker"],function () {
  "use strict";
  var $mod = this;
});
rtl.module("SysUtils",["System","JS"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  rtl.recNewT(this,"TFormatSettings",function () {
    this.CurrencyDecimals = 0;
    this.CurrencyFormat = 0;
    this.CurrencyString = "";
    this.DateSeparator = "\x00";
    this.DecimalSeparator = "";
    this.LongDateFormat = "";
    this.LongTimeFormat = "";
    this.NegCurrFormat = 0;
    this.ShortDateFormat = "";
    this.ShortTimeFormat = "";
    this.ThousandSeparator = "";
    this.TimeAMString = "";
    this.TimePMString = "";
    this.TimeSeparator = "\x00";
    this.TwoDigitYearCenturyWindow = 0;
    this.InitLocaleHandler = null;
    this.$new = function () {
      var r = Object.create(this);
      r.DateTimeToStrFormat = rtl.arraySetLength(null,"",2);
      r.LongDayNames = rtl.arraySetLength(null,"",7);
      r.LongMonthNames = rtl.arraySetLength(null,"",12);
      r.ShortDayNames = rtl.arraySetLength(null,"",7);
      r.ShortMonthNames = rtl.arraySetLength(null,"",12);
      return r;
    };
    this.$eq = function (b) {
      return (this.CurrencyDecimals === b.CurrencyDecimals) && (this.CurrencyFormat === b.CurrencyFormat) && (this.CurrencyString === b.CurrencyString) && (this.DateSeparator === b.DateSeparator) && rtl.arrayEq(this.DateTimeToStrFormat,b.DateTimeToStrFormat) && (this.DecimalSeparator === b.DecimalSeparator) && (this.LongDateFormat === b.LongDateFormat) && rtl.arrayEq(this.LongDayNames,b.LongDayNames) && rtl.arrayEq(this.LongMonthNames,b.LongMonthNames) && (this.LongTimeFormat === b.LongTimeFormat) && (this.NegCurrFormat === b.NegCurrFormat) && (this.ShortDateFormat === b.ShortDateFormat) && rtl.arrayEq(this.ShortDayNames,b.ShortDayNames) && rtl.arrayEq(this.ShortMonthNames,b.ShortMonthNames) && (this.ShortTimeFormat === b.ShortTimeFormat) && (this.ThousandSeparator === b.ThousandSeparator) && (this.TimeAMString === b.TimeAMString) && (this.TimePMString === b.TimePMString) && (this.TimeSeparator === b.TimeSeparator) && (this.TwoDigitYearCenturyWindow === b.TwoDigitYearCenturyWindow);
    };
    this.$assign = function (s) {
      this.CurrencyDecimals = s.CurrencyDecimals;
      this.CurrencyFormat = s.CurrencyFormat;
      this.CurrencyString = s.CurrencyString;
      this.DateSeparator = s.DateSeparator;
      this.DateTimeToStrFormat = s.DateTimeToStrFormat.slice(0);
      this.DecimalSeparator = s.DecimalSeparator;
      this.LongDateFormat = s.LongDateFormat;
      this.LongDayNames = s.LongDayNames.slice(0);
      this.LongMonthNames = s.LongMonthNames.slice(0);
      this.LongTimeFormat = s.LongTimeFormat;
      this.NegCurrFormat = s.NegCurrFormat;
      this.ShortDateFormat = s.ShortDateFormat;
      this.ShortDayNames = s.ShortDayNames.slice(0);
      this.ShortMonthNames = s.ShortMonthNames.slice(0);
      this.ShortTimeFormat = s.ShortTimeFormat;
      this.ThousandSeparator = s.ThousandSeparator;
      this.TimeAMString = s.TimeAMString;
      this.TimePMString = s.TimePMString;
      this.TimeSeparator = s.TimeSeparator;
      this.TwoDigitYearCenturyWindow = s.TwoDigitYearCenturyWindow;
      return this;
    };
    this.GetJSLocale = function () {
      return Intl.DateTimeFormat().resolvedOptions().locale;
    };
    this.Create = function () {
      var Result = $mod.TFormatSettings.$new();
      Result.$assign($mod.TFormatSettings.Create$1($mod.TFormatSettings.GetJSLocale()));
      return Result;
    };
    this.Create$1 = function (ALocale) {
      var Result = $mod.TFormatSettings.$new();
      Result.LongDayNames = $impl.DefaultLongDayNames.slice(0);
      Result.ShortDayNames = $impl.DefaultShortDayNames.slice(0);
      Result.ShortMonthNames = $impl.DefaultShortMonthNames.slice(0);
      Result.LongMonthNames = $impl.DefaultLongMonthNames.slice(0);
      Result.DateTimeToStrFormat[0] = "c";
      Result.DateTimeToStrFormat[1] = "f";
      Result.DateSeparator = "-";
      Result.TimeSeparator = ":";
      Result.ShortDateFormat = "yyyy-mm-dd";
      Result.LongDateFormat = "ddd, yyyy-mm-dd";
      Result.ShortTimeFormat = "hh:nn";
      Result.LongTimeFormat = "hh:nn:ss";
      Result.DecimalSeparator = ".";
      Result.ThousandSeparator = ",";
      Result.TimeAMString = "AM";
      Result.TimePMString = "PM";
      Result.TwoDigitYearCenturyWindow = 50;
      Result.CurrencyFormat = 0;
      Result.NegCurrFormat = 0;
      Result.CurrencyDecimals = 2;
      Result.CurrencyString = "$";
      if ($mod.TFormatSettings.InitLocaleHandler != null) $mod.TFormatSettings.InitLocaleHandler($mod.UpperCase(ALocale),$mod.TFormatSettings.$clone(Result));
      return Result;
    };
  },true);
  rtl.createClass(this,"Exception",pas.System.TObject,function () {
    this.$init = function () {
      pas.System.TObject.$init.call(this);
      this.fMessage = "";
    };
  });
  rtl.createClass(this,"EExternal",this.Exception,function () {
  });
  rtl.createClass(this,"EInvalidCast",this.Exception,function () {
  });
  rtl.createClass(this,"EIntError",this.EExternal,function () {
  });
  rtl.createClass(this,"ERangeError",this.EIntError,function () {
  });
  rtl.createClass(this,"EAbstractError",this.Exception,function () {
  });
  this.Trim = function (S) {
    return S.replace(/^[\s\uFEFF\xA0\x00-\x1f]+/,'').replace(/[\s\uFEFF\xA0\x00-\x1f]+$/,'');
  };
  this.UpperCase = function (s) {
    return s.toUpperCase();
  };
  this.LowerCase = function (s) {
    return s.toLowerCase();
  };
  this.TStringReplaceFlag = {"0": "rfReplaceAll", rfReplaceAll: 0, "1": "rfIgnoreCase", rfIgnoreCase: 1};
  this.StringReplace = function (aOriginal, aSearch, aReplace, Flags) {
    var Result = "";
    var REFlags = "";
    var REString = "";
    REFlags = "";
    if (0 in Flags) REFlags = "g";
    if (1 in Flags) REFlags = REFlags + "i";
    REString = aSearch.replace(new RegExp($impl.RESpecials,"g"),"\\$1");
    Result = aOriginal.replace(new RegExp(REString,REFlags),aReplace);
    return Result;
  };
  this.IntToStr = function (Value) {
    var Result = "";
    Result = "" + Value;
    return Result;
  };
  this.TryStrToInt$2 = function (S, res) {
    var Result = false;
    Result = $impl.IntTryStrToInt(S,res,$mod.FormatSettings.DecimalSeparator);
    return Result;
  };
  this.StrToIntDef = function (S, aDef) {
    var Result = 0;
    var R = 0;
    if ($mod.TryStrToInt$2(S,{get: function () {
        return R;
      }, set: function (v) {
        R = v;
      }})) {
      Result = R}
     else Result = aDef;
    return Result;
  };
  this.TimeSeparator = "\x00";
  this.DateSeparator = "\x00";
  this.ShortDateFormat = "";
  this.LongDateFormat = "";
  this.ShortTimeFormat = "";
  this.LongTimeFormat = "";
  this.DecimalSeparator = "";
  this.ThousandSeparator = "";
  this.TimeAMString = "";
  this.TimePMString = "";
  this.ShortMonthNames = rtl.arraySetLength(null,"",12);
  this.LongMonthNames = rtl.arraySetLength(null,"",12);
  this.ShortDayNames = rtl.arraySetLength(null,"",7);
  this.LongDayNames = rtl.arraySetLength(null,"",7);
  this.FormatSettings = this.TFormatSettings.$new();
  this.CurrencyFormat = 0;
  this.NegCurrFormat = 0;
  this.CurrencyDecimals = 0;
  this.CurrencyString = "";
  $mod.$implcode = function () {
    $impl.DefaultShortMonthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    $impl.DefaultLongMonthNames = ["January","February","March","April","May","June","July","August","September","October","November","December"];
    $impl.DefaultShortDayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
    $impl.DefaultLongDayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
    $impl.RESpecials = "([\\$\\+\\[\\]\\(\\)\\\\\\.\\*\\^\\?\\|])";
    $impl.IntTryStrToInt = function (S, res, aSep) {
      var Result = false;
      var Radix = 10;
      var N = "";
      var J = undefined;
      N = S;
      if ((pas.System.Pos(aSep,N) !== 0) || (pas.System.Pos(".",N) !== 0)) return false;
      var $tmp = pas.System.Copy(N,1,1);
      if ($tmp === "$") {
        Radix = 16}
       else if ($tmp === "&") {
        Radix = 8}
       else if ($tmp === "%") Radix = 2;
      if ((Radix !== 16) && (pas.System.Pos("e",$mod.LowerCase(N)) !== 0)) return false;
      if (Radix !== 10) pas.System.Delete({get: function () {
          return N;
        }, set: function (v) {
          N = v;
        }},1,1);
      J = parseInt(N,Radix);
      Result = !isNaN(J);
      if (Result) res.set(rtl.trunc(J));
      return Result;
    };
    $impl.InitGlobalFormatSettings = function () {
      $mod.FormatSettings.$assign($mod.TFormatSettings.Create());
      $mod.TimeSeparator = $mod.FormatSettings.TimeSeparator;
      $mod.DateSeparator = $mod.FormatSettings.DateSeparator;
      $mod.ShortDateFormat = $mod.FormatSettings.ShortDateFormat;
      $mod.LongDateFormat = $mod.FormatSettings.LongDateFormat;
      $mod.ShortTimeFormat = $mod.FormatSettings.ShortTimeFormat;
      $mod.LongTimeFormat = $mod.FormatSettings.LongTimeFormat;
      $mod.DecimalSeparator = $mod.FormatSettings.DecimalSeparator;
      $mod.ThousandSeparator = $mod.FormatSettings.ThousandSeparator;
      $mod.TimeAMString = $mod.FormatSettings.TimeAMString;
      $mod.TimePMString = $mod.FormatSettings.TimePMString;
      $mod.CurrencyFormat = $mod.FormatSettings.CurrencyFormat;
      $mod.NegCurrFormat = $mod.FormatSettings.NegCurrFormat;
      $mod.CurrencyDecimals = $mod.FormatSettings.CurrencyDecimals;
      $mod.CurrencyString = $mod.FormatSettings.CurrencyString;
    };
    $impl.DoClassRef = function (C) {
      if (C === null) ;
    };
  };
  $mod.$init = function () {
    (function () {
      $impl.InitGlobalFormatSettings();
    })();
    $impl.DoClassRef($mod.EInvalidCast);
    $impl.DoClassRef($mod.EAbstractError);
    $impl.DoClassRef($mod.ERangeError);
    $mod.ShortMonthNames = $impl.DefaultShortMonthNames.slice(0);
    $mod.LongMonthNames = $impl.DefaultLongMonthNames.slice(0);
    $mod.ShortDayNames = $impl.DefaultShortDayNames.slice(0);
    $mod.LongDayNames = $impl.DefaultLongDayNames.slice(0);
  };
},[]);
rtl.module("Math",["System"],function () {
  "use strict";
  var $mod = this;
  this.Ceil = function (A) {
    var Result = 0;
    Result = pas.System.Trunc(Math.ceil(A));
    return Result;
  };
});
rtl.module("TsTypes",["System"],function () {
  "use strict";
  var $mod = this;
  this.GameTagline = "Design it. Fly it. Find out why.";
  this.G0 = 9.80665;
  this.ArrayWattsPerM2 = 250.0;
  this.ArrayKgPerM2 = 3.4;
  this.ArrayCostPerM2 = 0.32;
  this.BatteryWhPerKg = 130.0;
  this.BatteryCostPerWh = 0.0022;
  this.RtgWatts = 110.0;
  this.RtgKg = 45.0;
  this.RtgCostM = 95.0;
  this.RtgDecayPerYear = 0.03;
  this.LinkK = 0.0012;
  this.WrapFraction = 0.23;
  this.HarnessFraction = 0.07;
  this.DvMargin = 0.10;
  this.AuKm = 149597870.7;
  this.LightSecondsPerAu = 499.0;
  this.TMeasure = {"0": "mImaging", mImaging: 0, "1": "mSpectral", mSpectral: 1, "2": "mThermal", mThermal: 2, "3": "mRadar", mRadar: 3, "4": "mTopo", mTopo: 4, "5": "mVolatiles", mVolatiles: 5, "6": "mAtmos", mAtmos: 6, "7": "mFields", mFields: 7, "8": "mService", mService: 8};
  this.TBusClass = {"0": "bcCube", bcCube: 0, "1": "bcSmall", bcSmall: 1, "2": "bcMedium", bcMedium: 2, "3": "bcLarge", bcLarge: 3};
  this.TLvMode = {"0": "lvLEO", lvLEO: 0, "1": "lvSSO", lvSSO: 1, "2": "lvGTO", lvGTO: 2, "3": "lvC3", lvC3: 3};
  this.TSeverity = {"0": "svGood", svGood: 0, "1": "svInfo", svInfo: 1, "2": "svWarn", svWarn: 2, "3": "svBlock", svBlock: 3};
  this.TRole = {"0": "roPM", roPM: 0, "1": "roScience", roScience: 1, "2": "roSpacecraft", roSpacecraft: 2, "3": "roOps", roOps: 3};
  this.TDifficulty = {"0": "dfCadet", dfCadet: 0, "1": "dfEngineer", dfEngineer: 1, "2": "dfChief", dfChief: 2};
  this.TPartKind = {"0": "pkBus", pkBus: 0, "1": "pkPropulsion", pkPropulsion: 1, "2": "pkAdcs", pkAdcs: 2, "3": "pkThermal", pkThermal: 3, "4": "pkComputer", pkComputer: 4, "5": "pkShield", pkShield: 5, "6": "pkAntenna", pkAntenna: 6, "7": "pkBand", pkBand: 7, "8": "pkTx", pkTx: 8, "9": "pkGround", pkGround: 9, "10": "pkRisk", pkRisk: 10, "11": "pkSchedule", pkSchedule: 11};
  rtl.recNewT(this,"TInstrument",function () {
    this.Id = "";
    this.Name = "";
    this.Analog = "";
    this.Blurb = "";
    this.MassKg = 0.0;
    this.PowerW = 0.0;
    this.CostM = 0.0;
    this.DataMbps = 0.0;
    this.Duty = 0.0;
    this.DevYears = 0.0;
    this.NeedsFinePointing = false;
    this.NeedsCooling = false;
    this.NeedsHGA = false;
    this.MinBus = 0;
    this.$new = function () {
      var r = Object.create(this);
      r.Value = rtl.arraySetLength(null,0.0,9);
      return r;
    };
    this.$eq = function (b) {
      return (this.Id === b.Id) && (this.Name === b.Name) && (this.Analog === b.Analog) && (this.Blurb === b.Blurb) && (this.MassKg === b.MassKg) && (this.PowerW === b.PowerW) && (this.CostM === b.CostM) && (this.DataMbps === b.DataMbps) && (this.Duty === b.Duty) && (this.DevYears === b.DevYears) && rtl.arrayEq(this.Value,b.Value) && (this.NeedsFinePointing === b.NeedsFinePointing) && (this.NeedsCooling === b.NeedsCooling) && (this.NeedsHGA === b.NeedsHGA) && (this.MinBus === b.MinBus);
    };
    this.$assign = function (s) {
      this.Id = s.Id;
      this.Name = s.Name;
      this.Analog = s.Analog;
      this.Blurb = s.Blurb;
      this.MassKg = s.MassKg;
      this.PowerW = s.PowerW;
      this.CostM = s.CostM;
      this.DataMbps = s.DataMbps;
      this.Duty = s.Duty;
      this.DevYears = s.DevYears;
      this.Value = s.Value.slice(0);
      this.NeedsFinePointing = s.NeedsFinePointing;
      this.NeedsCooling = s.NeedsCooling;
      this.NeedsHGA = s.NeedsHGA;
      this.MinBus = s.MinBus;
      return this;
    };
  });
  rtl.recNewT(this,"TPart",function () {
    this.Kind = 0;
    this.Id = "";
    this.Name = "";
    this.Analog = "";
    this.Blurb = "";
    this.MassKg = 0.0;
    this.PowerW = 0.0;
    this.CostM = 0.0;
    this.DevYears = 0.0;
    this.A = 0.0;
    this.B = 0.0;
    this.C = 0.0;
    this.D = 0.0;
    this.E = 0.0;
    this.F = 0.0;
    this.G = 0.0;
    this.Tier = 0;
    this.MinBus = 0;
    this.$eq = function (b) {
      return (this.Kind === b.Kind) && (this.Id === b.Id) && (this.Name === b.Name) && (this.Analog === b.Analog) && (this.Blurb === b.Blurb) && (this.MassKg === b.MassKg) && (this.PowerW === b.PowerW) && (this.CostM === b.CostM) && (this.DevYears === b.DevYears) && (this.A === b.A) && (this.B === b.B) && (this.C === b.C) && (this.D === b.D) && (this.E === b.E) && (this.F === b.F) && (this.G === b.G) && (this.Tier === b.Tier) && (this.MinBus === b.MinBus);
    };
    this.$assign = function (s) {
      this.Kind = s.Kind;
      this.Id = s.Id;
      this.Name = s.Name;
      this.Analog = s.Analog;
      this.Blurb = s.Blurb;
      this.MassKg = s.MassKg;
      this.PowerW = s.PowerW;
      this.CostM = s.CostM;
      this.DevYears = s.DevYears;
      this.A = s.A;
      this.B = s.B;
      this.C = s.C;
      this.D = s.D;
      this.E = s.E;
      this.F = s.F;
      this.G = s.G;
      this.Tier = s.Tier;
      this.MinBus = s.MinBus;
      return this;
    };
  });
  rtl.recNewT(this,"TLauncher",function () {
    this.Id = "";
    this.Name = "";
    this.Agency = "";
    this.Blurb = "";
    this.LeoKg = 0.0;
    this.SsoKg = 0.0;
    this.GtoKg = 0.0;
    this.C3ZeroKg = 0.0;
    this.C3K = 0.0;
    this.CostM = 0.0;
    this.Reliability = 0.0;
    this.MaxBus = 0;
    this.Rideshare = false;
    this.Size = 0;
    this.$eq = function (b) {
      return (this.Id === b.Id) && (this.Name === b.Name) && (this.Agency === b.Agency) && (this.Blurb === b.Blurb) && (this.LeoKg === b.LeoKg) && (this.SsoKg === b.SsoKg) && (this.GtoKg === b.GtoKg) && (this.C3ZeroKg === b.C3ZeroKg) && (this.C3K === b.C3K) && (this.CostM === b.CostM) && (this.Reliability === b.Reliability) && (this.MaxBus === b.MaxBus) && (this.Rideshare === b.Rideshare) && (this.Size === b.Size);
    };
    this.$assign = function (s) {
      this.Id = s.Id;
      this.Name = s.Name;
      this.Agency = s.Agency;
      this.Blurb = s.Blurb;
      this.LeoKg = s.LeoKg;
      this.SsoKg = s.SsoKg;
      this.GtoKg = s.GtoKg;
      this.C3ZeroKg = s.C3ZeroKg;
      this.C3K = s.C3K;
      this.CostM = s.CostM;
      this.Reliability = s.Reliability;
      this.MaxBus = s.MaxBus;
      this.Rideshare = s.Rideshare;
      this.Size = s.Size;
      return this;
    };
  });
  rtl.recNewT(this,"TOrbit",function () {
    this.Id = "";
    this.Name = "";
    this.Blurb = "";
    this.Why = "";
    this.AltKm = 0.0;
    this.ApoKm = 0.0;
    this.IncDeg = 0.0;
    this.PeriodHr = 0.0;
    this.EclipseFrac = 0.0;
    this.MaxEclipseHr = 0.0;
    this.Coverage = 0.0;
    this.EventsSeen = 0;
    this.EventsTotal = 0;
    this.TauFactor = 0.0;
    this.DataFactor = 0.0;
    this.CommFactor = 0.0;
    this.RangeKm = 0.0;
    this.DvInsert = 0.0;
    this.DvPerYear = 0.0;
    this.LvMode = 0;
    this.C3 = 0.0;
    this.ExtraYears = 0.0;
    this.InsertRisk = 0.0;
    this.RadLevel = 0;
    this.RadLifeYears = 0.0;
    this.DragLifeYears = 0.0;
    this.NeedsDeorbit = false;
    this.IsGeo = false;
    this.GeoLon = 0.0;
    this.$new = function () {
      var r = Object.create(this);
      r.Factor = rtl.arraySetLength(null,0.0,9);
      r.Base = rtl.arraySetLength(null,0.0,9);
      return r;
    };
    this.$eq = function (b) {
      return (this.Id === b.Id) && (this.Name === b.Name) && (this.Blurb === b.Blurb) && (this.Why === b.Why) && (this.AltKm === b.AltKm) && (this.ApoKm === b.ApoKm) && (this.IncDeg === b.IncDeg) && (this.PeriodHr === b.PeriodHr) && (this.EclipseFrac === b.EclipseFrac) && (this.MaxEclipseHr === b.MaxEclipseHr) && (this.Coverage === b.Coverage) && rtl.arrayEq(this.Factor,b.Factor) && rtl.arrayEq(this.Base,b.Base) && (this.EventsSeen === b.EventsSeen) && (this.EventsTotal === b.EventsTotal) && (this.TauFactor === b.TauFactor) && (this.DataFactor === b.DataFactor) && (this.CommFactor === b.CommFactor) && (this.RangeKm === b.RangeKm) && (this.DvInsert === b.DvInsert) && (this.DvPerYear === b.DvPerYear) && (this.LvMode === b.LvMode) && (this.C3 === b.C3) && (this.ExtraYears === b.ExtraYears) && (this.InsertRisk === b.InsertRisk) && (this.RadLevel === b.RadLevel) && (this.RadLifeYears === b.RadLifeYears) && (this.DragLifeYears === b.DragLifeYears) && (this.NeedsDeorbit === b.NeedsDeorbit) && (this.IsGeo === b.IsGeo) && (this.GeoLon === b.GeoLon);
    };
    this.$assign = function (s) {
      this.Id = s.Id;
      this.Name = s.Name;
      this.Blurb = s.Blurb;
      this.Why = s.Why;
      this.AltKm = s.AltKm;
      this.ApoKm = s.ApoKm;
      this.IncDeg = s.IncDeg;
      this.PeriodHr = s.PeriodHr;
      this.EclipseFrac = s.EclipseFrac;
      this.MaxEclipseHr = s.MaxEclipseHr;
      this.Coverage = s.Coverage;
      this.Factor = s.Factor.slice(0);
      this.Base = s.Base.slice(0);
      this.EventsSeen = s.EventsSeen;
      this.EventsTotal = s.EventsTotal;
      this.TauFactor = s.TauFactor;
      this.DataFactor = s.DataFactor;
      this.CommFactor = s.CommFactor;
      this.RangeKm = s.RangeKm;
      this.DvInsert = s.DvInsert;
      this.DvPerYear = s.DvPerYear;
      this.LvMode = s.LvMode;
      this.C3 = s.C3;
      this.ExtraYears = s.ExtraYears;
      this.InsertRisk = s.InsertRisk;
      this.RadLevel = s.RadLevel;
      this.RadLifeYears = s.RadLifeYears;
      this.DragLifeYears = s.DragLifeYears;
      this.NeedsDeorbit = s.NeedsDeorbit;
      this.IsGeo = s.IsGeo;
      this.GeoLon = s.GeoLon;
      return this;
    };
  });
  rtl.recNewT(this,"TTransfer",function () {
    this.Id = "";
    this.Name = "";
    this.Blurb = "";
    this.C3 = 0.0;
    this.CruiseYears = 0.0;
    this.DvFactor = 0.0;
    this.HotFlyby = false;
    this.$eq = function (b) {
      return (this.Id === b.Id) && (this.Name === b.Name) && (this.Blurb === b.Blurb) && (this.C3 === b.C3) && (this.CruiseYears === b.CruiseYears) && (this.DvFactor === b.DvFactor) && (this.HotFlyby === b.HotFlyby);
    };
    this.$assign = function (s) {
      this.Id = s.Id;
      this.Name = s.Name;
      this.Blurb = s.Blurb;
      this.C3 = s.C3;
      this.CruiseYears = s.CruiseYears;
      this.DvFactor = s.DvFactor;
      this.HotFlyby = s.HotFlyby;
      return this;
    };
  });
  rtl.recNewT(this,"TGlossaryItem",function () {
    this.Term = "";
    this.Plain = "";
    this.Why = "";
    this.$eq = function (b) {
      return (this.Term === b.Term) && (this.Plain === b.Plain) && (this.Why === b.Why);
    };
    this.$assign = function (s) {
      this.Term = s.Term;
      this.Plain = s.Plain;
      this.Why = s.Why;
      return this;
    };
  });
  rtl.recNewT(this,"TEarthEvent",function () {
    this.Title = "";
    this.Category = "";
    this.Date = "";
    this.Lat = 0.0;
    this.Lon = 0.0;
    this.$eq = function (b) {
      return (this.Title === b.Title) && (this.Category === b.Category) && (this.Date === b.Date) && (this.Lat === b.Lat) && (this.Lon === b.Lon);
    };
    this.$assign = function (s) {
      this.Title = s.Title;
      this.Category = s.Category;
      this.Date = s.Date;
      this.Lat = s.Lat;
      this.Lon = s.Lon;
      return this;
    };
  });
  rtl.recNewT(this,"TSpaceWeather",function () {
    this.Kind = "";
    this.Date = "";
    this.ClassType = "";
    this.Strength = 0.0;
    this.$eq = function (b) {
      return (this.Kind === b.Kind) && (this.Date === b.Date) && (this.ClassType === b.ClassType) && (this.Strength === b.Strength);
    };
    this.$assign = function (s) {
      this.Kind = s.Kind;
      this.Date = s.Date;
      this.ClassType = s.ClassType;
      this.Strength = s.Strength;
      return this;
    };
  });
  rtl.recNewT(this,"TAnalog",function () {
    this.Name = "";
    this.Agency = "";
    this.Year = "";
    this.Blurb = "";
    this.Url = "";
    this.MassKg = 0.0;
    this.CostM = 0.0;
    this.Instruments = 0;
    this.$eq = function (b) {
      return (this.Name === b.Name) && (this.Agency === b.Agency) && (this.Year === b.Year) && (this.Blurb === b.Blurb) && (this.Url === b.Url) && (this.MassKg === b.MassKg) && (this.CostM === b.CostM) && (this.Instruments === b.Instruments);
    };
    this.$assign = function (s) {
      this.Name = s.Name;
      this.Agency = s.Agency;
      this.Year = s.Year;
      this.Blurb = s.Blurb;
      this.Url = s.Url;
      this.MassKg = s.MassKg;
      this.CostM = s.CostM;
      this.Instruments = s.Instruments;
      return this;
    };
  });
  rtl.recNewT(this,"TScenario",function () {
    this.Id = "";
    this.Name = "";
    this.Tagline = "";
    this.Body = "";
    this.Brief = "";
    this.Objective = "";
    this.Level = 0;
    this.CostCapM = 0.0;
    this.DeadlineYears = 0.0;
    this.WindowYears = 0.0;
    this.WindowPeriod = 0.0;
    this.ArriveBy = false;
    this.LateFactor = 0.0;
    this.MinLife = 0.0;
    this.MaxLife = 0.0;
    this.DefaultLife = 0.0;
    this.SunAU = 0.0;
    this.EarthMinAU = 0.0;
    this.EarthMaxAU = 0.0;
    this.SynodicDays = 0.0;
    this.NearEarth = false;
    this.DataScale = 0.0;
    this.HeaterW = 0.0;
    this.ColdWorld = false;
    this.AllowRTG = false;
    this.AllowSEP = false;
    this.SepDvFactor = 0.0;
    this.SepExtraYears = 0.0;
    this.FullScience = 0.0;
    this.ThresholdPct = 0.0;
    this.TauYears = 0.0;
    this.UsesEonet = false;
    this.UsesApophis = false;
    this.$new = function () {
      var r = Object.create(this);
      r.Weight = rtl.arraySetLength(null,0.0,9);
      r.Orbits = [];
      r.Transfers = [];
      r.Instruments = [];
      r.Analogs = [];
      r.Facts = [];
      return r;
    };
    this.$eq = function (b) {
      return (this.Id === b.Id) && (this.Name === b.Name) && (this.Tagline === b.Tagline) && (this.Body === b.Body) && (this.Brief === b.Brief) && (this.Objective === b.Objective) && (this.Level === b.Level) && (this.CostCapM === b.CostCapM) && (this.DeadlineYears === b.DeadlineYears) && (this.WindowYears === b.WindowYears) && (this.WindowPeriod === b.WindowPeriod) && (this.ArriveBy === b.ArriveBy) && (this.LateFactor === b.LateFactor) && (this.MinLife === b.MinLife) && (this.MaxLife === b.MaxLife) && (this.DefaultLife === b.DefaultLife) && (this.SunAU === b.SunAU) && (this.EarthMinAU === b.EarthMinAU) && (this.EarthMaxAU === b.EarthMaxAU) && (this.SynodicDays === b.SynodicDays) && (this.NearEarth === b.NearEarth) && (this.DataScale === b.DataScale) && (this.HeaterW === b.HeaterW) && (this.ColdWorld === b.ColdWorld) && (this.AllowRTG === b.AllowRTG) && (this.AllowSEP === b.AllowSEP) && (this.SepDvFactor === b.SepDvFactor) && (this.SepExtraYears === b.SepExtraYears) && rtl.arrayEq(this.Weight,b.Weight) && (this.FullScience === b.FullScience) && (this.ThresholdPct === b.ThresholdPct) && (this.TauYears === b.TauYears) && (this.Orbits === b.Orbits) && (this.Transfers === b.Transfers) && (this.Instruments === b.Instruments) && (this.Analogs === b.Analogs) && (this.Facts === b.Facts) && (this.UsesEonet === b.UsesEonet) && (this.UsesApophis === b.UsesApophis);
    };
    this.$assign = function (s) {
      this.Id = s.Id;
      this.Name = s.Name;
      this.Tagline = s.Tagline;
      this.Body = s.Body;
      this.Brief = s.Brief;
      this.Objective = s.Objective;
      this.Level = s.Level;
      this.CostCapM = s.CostCapM;
      this.DeadlineYears = s.DeadlineYears;
      this.WindowYears = s.WindowYears;
      this.WindowPeriod = s.WindowPeriod;
      this.ArriveBy = s.ArriveBy;
      this.LateFactor = s.LateFactor;
      this.MinLife = s.MinLife;
      this.MaxLife = s.MaxLife;
      this.DefaultLife = s.DefaultLife;
      this.SunAU = s.SunAU;
      this.EarthMinAU = s.EarthMinAU;
      this.EarthMaxAU = s.EarthMaxAU;
      this.SynodicDays = s.SynodicDays;
      this.NearEarth = s.NearEarth;
      this.DataScale = s.DataScale;
      this.HeaterW = s.HeaterW;
      this.ColdWorld = s.ColdWorld;
      this.AllowRTG = s.AllowRTG;
      this.AllowSEP = s.AllowSEP;
      this.SepDvFactor = s.SepDvFactor;
      this.SepExtraYears = s.SepExtraYears;
      this.Weight = s.Weight.slice(0);
      this.FullScience = s.FullScience;
      this.ThresholdPct = s.ThresholdPct;
      this.TauYears = s.TauYears;
      this.Orbits = rtl.arrayRef(s.Orbits);
      this.Transfers = rtl.arrayRef(s.Transfers);
      this.Instruments = rtl.arrayRef(s.Instruments);
      this.Analogs = rtl.arrayRef(s.Analogs);
      this.Facts = rtl.arrayRef(s.Facts);
      this.UsesEonet = s.UsesEonet;
      this.UsesApophis = s.UsesApophis;
      return this;
    };
  });
  rtl.recNewT(this,"TDesign",function () {
    this.Scenario = 0;
    this.Difficulty = 0;
    this.Sandbox = false;
    this.Orbit = 0;
    this.Transfer = 0;
    this.Launcher = 0;
    this.SolarM2 = 0.0;
    this.RtgCount = 0;
    this.BatteryWh = 0.0;
    this.LifeYears = 0.0;
    this.ReservePct = 0.0;
    this.Seed = 0;
    this.$new = function () {
      var r = Object.create(this);
      r.Part = rtl.arraySetLength(null,0,12);
      r.Instr = [];
      return r;
    };
    this.$eq = function (b) {
      return (this.Scenario === b.Scenario) && (this.Difficulty === b.Difficulty) && (this.Sandbox === b.Sandbox) && (this.Orbit === b.Orbit) && (this.Transfer === b.Transfer) && rtl.arrayEq(this.Part,b.Part) && (this.Launcher === b.Launcher) && (this.Instr === b.Instr) && (this.SolarM2 === b.SolarM2) && (this.RtgCount === b.RtgCount) && (this.BatteryWh === b.BatteryWh) && (this.LifeYears === b.LifeYears) && (this.ReservePct === b.ReservePct) && (this.Seed === b.Seed);
    };
    this.$assign = function (s) {
      this.Scenario = s.Scenario;
      this.Difficulty = s.Difficulty;
      this.Sandbox = s.Sandbox;
      this.Orbit = s.Orbit;
      this.Transfer = s.Transfer;
      this.Part = s.Part.slice(0);
      this.Launcher = s.Launcher;
      this.Instr = rtl.arrayRef(s.Instr);
      this.SolarM2 = s.SolarM2;
      this.RtgCount = s.RtgCount;
      this.BatteryWh = s.BatteryWh;
      this.LifeYears = s.LifeYears;
      this.ReservePct = s.ReservePct;
      this.Seed = s.Seed;
      return this;
    };
  });
  rtl.recNewT(this,"TFinding",function () {
    this.Sev = 0;
    this.Code = "";
    this.Title = "";
    this.Why = "";
    this.Fix = "";
    this.Owner = 0;
    this.$eq = function (b) {
      return (this.Sev === b.Sev) && (this.Code === b.Code) && (this.Title === b.Title) && (this.Why === b.Why) && (this.Fix === b.Fix) && (this.Owner === b.Owner);
    };
    this.$assign = function (s) {
      this.Sev = s.Sev;
      this.Code = s.Code;
      this.Title = s.Title;
      this.Why = s.Why;
      this.Fix = s.Fix;
      this.Owner = s.Owner;
      return this;
    };
  });
  rtl.recNewT(this,"TLine",function () {
    this.Name = "";
    this.Value = 0.0;
    this.$eq = function (b) {
      return (this.Name === b.Name) && (this.Value === b.Value);
    };
    this.$assign = function (s) {
      this.Name = s.Name;
      this.Value = s.Value;
      return this;
    };
  });
  rtl.recNewT(this,"TAnalysis",function () {
    this.PayloadKg = 0.0;
    this.DryKg = 0.0;
    this.PropKg = 0.0;
    this.WetKg = 0.0;
    this.LvCapKg = 0.0;
    this.MassMargin = 0.0;
    this.SolarW = 0.0;
    this.RtgW = 0.0;
    this.GenW = 0.0;
    this.GenAvgW = 0.0;
    this.LoadAvgW = 0.0;
    this.LoadPeakW = 0.0;
    this.PowerMargin = 0.0;
    this.BatteryNeedWh = 0.0;
    this.DvNeed = 0.0;
    this.DvInsert = 0.0;
    this.DvKeep = 0.0;
    this.DvDisposal = 0.0;
    this.PropFeasible = false;
    this.GenGbitDay = 0.0;
    this.RateAvgMbps = 0.0;
    this.RateMinMbps = 0.0;
    this.ContactHr = 0.0;
    this.DownGbitDay = 0.0;
    this.DataReturn = 0.0;
    this.StorageGbit = 0.0;
    this.StorageDays = 0.0;
    this.LightDelayMin = 0.0;
    this.CostHardware = 0.0;
    this.CostWraps = 0.0;
    this.CostLaunch = 0.0;
    this.CostOps = 0.0;
    this.CostReserve = 0.0;
    this.CostTotal = 0.0;
    this.CapM = 0.0;
    this.CostMargin = 0.0;
    this.DevCostM = 0.0;
    this.OpsPerYearM = 0.0;
    this.SlipCostM = 0.0;
    this.DevYears = 0.0;
    this.LaunchYear = 0.0;
    this.CruiseYears = 0.0;
    this.ArriveYear = 0.0;
    this.LifeYears = 0.0;
    this.SlipYears = 0.0;
    this.MissedDeadline = false;
    this.SciencePct = 0.0;
    this.ScienceMaxPct = 0.0;
    this.TauYears = 0.0;
    this.LifeLimitYears = 0.0;
    this.LifeLimitWhy = "";
    this.PointingTier = 0;
    this.RadExposure = 0;
    this.LaunchSuccess = 0.0;
    this.InsertSuccess = 0.0;
    this.YearSurvival = 0.0;
    this.SuccessProb = 0.0;
    this.AnomalyRate = 0.0;
    this.FatalShare = 0.0;
    this.InstrumentCount = 0;
    this.Blockers = 0;
    this.Warnings = 0;
    this.$new = function () {
      var r = Object.create(this);
      r.MassLines = [];
      r.PowerLines = [];
      r.CostLines = [];
      r.Capability = rtl.arraySetLength(null,0.0,9);
      r.InstrQuality = [];
      r.Findings = [];
      return r;
    };
    this.$eq = function (b) {
      return (this.PayloadKg === b.PayloadKg) && (this.DryKg === b.DryKg) && (this.PropKg === b.PropKg) && (this.WetKg === b.WetKg) && (this.LvCapKg === b.LvCapKg) && (this.MassMargin === b.MassMargin) && (this.MassLines === b.MassLines) && (this.SolarW === b.SolarW) && (this.RtgW === b.RtgW) && (this.GenW === b.GenW) && (this.GenAvgW === b.GenAvgW) && (this.LoadAvgW === b.LoadAvgW) && (this.LoadPeakW === b.LoadPeakW) && (this.PowerMargin === b.PowerMargin) && (this.BatteryNeedWh === b.BatteryNeedWh) && (this.PowerLines === b.PowerLines) && (this.DvNeed === b.DvNeed) && (this.DvInsert === b.DvInsert) && (this.DvKeep === b.DvKeep) && (this.DvDisposal === b.DvDisposal) && (this.PropFeasible === b.PropFeasible) && (this.GenGbitDay === b.GenGbitDay) && (this.RateAvgMbps === b.RateAvgMbps) && (this.RateMinMbps === b.RateMinMbps) && (this.ContactHr === b.ContactHr) && (this.DownGbitDay === b.DownGbitDay) && (this.DataReturn === b.DataReturn) && (this.StorageGbit === b.StorageGbit) && (this.StorageDays === b.StorageDays) && (this.LightDelayMin === b.LightDelayMin) && (this.CostHardware === b.CostHardware) && (this.CostWraps === b.CostWraps) && (this.CostLaunch === b.CostLaunch) && (this.CostOps === b.CostOps) && (this.CostReserve === b.CostReserve) && (this.CostTotal === b.CostTotal) && (this.CapM === b.CapM) && (this.CostMargin === b.CostMargin) && (this.DevCostM === b.DevCostM) && (this.OpsPerYearM === b.OpsPerYearM) && (this.SlipCostM === b.SlipCostM) && (this.CostLines === b.CostLines) && (this.DevYears === b.DevYears) && (this.LaunchYear === b.LaunchYear) && (this.CruiseYears === b.CruiseYears) && (this.ArriveYear === b.ArriveYear) && (this.LifeYears === b.LifeYears) && (this.SlipYears === b.SlipYears) && (this.MissedDeadline === b.MissedDeadline) && rtl.arrayEq(this.Capability,b.Capability) && (this.InstrQuality === b.InstrQuality) && (this.SciencePct === b.SciencePct) && (this.ScienceMaxPct === b.ScienceMaxPct) && (this.TauYears === b.TauYears) && (this.LifeLimitYears === b.LifeLimitYears) && (this.LifeLimitWhy === b.LifeLimitWhy) && (this.PointingTier === b.PointingTier) && (this.RadExposure === b.RadExposure) && (this.LaunchSuccess === b.LaunchSuccess) && (this.InsertSuccess === b.InsertSuccess) && (this.YearSurvival === b.YearSurvival) && (this.SuccessProb === b.SuccessProb) && (this.AnomalyRate === b.AnomalyRate) && (this.FatalShare === b.FatalShare) && (this.InstrumentCount === b.InstrumentCount) && (this.Findings === b.Findings) && (this.Blockers === b.Blockers) && (this.Warnings === b.Warnings);
    };
    this.$assign = function (s) {
      this.PayloadKg = s.PayloadKg;
      this.DryKg = s.DryKg;
      this.PropKg = s.PropKg;
      this.WetKg = s.WetKg;
      this.LvCapKg = s.LvCapKg;
      this.MassMargin = s.MassMargin;
      this.MassLines = rtl.arrayRef(s.MassLines);
      this.SolarW = s.SolarW;
      this.RtgW = s.RtgW;
      this.GenW = s.GenW;
      this.GenAvgW = s.GenAvgW;
      this.LoadAvgW = s.LoadAvgW;
      this.LoadPeakW = s.LoadPeakW;
      this.PowerMargin = s.PowerMargin;
      this.BatteryNeedWh = s.BatteryNeedWh;
      this.PowerLines = rtl.arrayRef(s.PowerLines);
      this.DvNeed = s.DvNeed;
      this.DvInsert = s.DvInsert;
      this.DvKeep = s.DvKeep;
      this.DvDisposal = s.DvDisposal;
      this.PropFeasible = s.PropFeasible;
      this.GenGbitDay = s.GenGbitDay;
      this.RateAvgMbps = s.RateAvgMbps;
      this.RateMinMbps = s.RateMinMbps;
      this.ContactHr = s.ContactHr;
      this.DownGbitDay = s.DownGbitDay;
      this.DataReturn = s.DataReturn;
      this.StorageGbit = s.StorageGbit;
      this.StorageDays = s.StorageDays;
      this.LightDelayMin = s.LightDelayMin;
      this.CostHardware = s.CostHardware;
      this.CostWraps = s.CostWraps;
      this.CostLaunch = s.CostLaunch;
      this.CostOps = s.CostOps;
      this.CostReserve = s.CostReserve;
      this.CostTotal = s.CostTotal;
      this.CapM = s.CapM;
      this.CostMargin = s.CostMargin;
      this.DevCostM = s.DevCostM;
      this.OpsPerYearM = s.OpsPerYearM;
      this.SlipCostM = s.SlipCostM;
      this.CostLines = rtl.arrayRef(s.CostLines);
      this.DevYears = s.DevYears;
      this.LaunchYear = s.LaunchYear;
      this.CruiseYears = s.CruiseYears;
      this.ArriveYear = s.ArriveYear;
      this.LifeYears = s.LifeYears;
      this.SlipYears = s.SlipYears;
      this.MissedDeadline = s.MissedDeadline;
      this.Capability = s.Capability.slice(0);
      this.InstrQuality = rtl.arrayRef(s.InstrQuality);
      this.SciencePct = s.SciencePct;
      this.ScienceMaxPct = s.ScienceMaxPct;
      this.TauYears = s.TauYears;
      this.LifeLimitYears = s.LifeLimitYears;
      this.LifeLimitWhy = s.LifeLimitWhy;
      this.PointingTier = s.PointingTier;
      this.RadExposure = s.RadExposure;
      this.LaunchSuccess = s.LaunchSuccess;
      this.InsertSuccess = s.InsertSuccess;
      this.YearSurvival = s.YearSurvival;
      this.SuccessProb = s.SuccessProb;
      this.AnomalyRate = s.AnomalyRate;
      this.FatalShare = s.FatalShare;
      this.InstrumentCount = s.InstrumentCount;
      this.Findings = rtl.arrayRef(s.Findings);
      this.Blockers = s.Blockers;
      this.Warnings = s.Warnings;
      return this;
    };
  });
  this.MeasureName = ["Imaging","Composition","Thermal","Radar","Topography & gravity","Volatiles & ice","Atmosphere & weather","Fields & particles","Relay service"];
  this.MeasureHint = ["Pictures of the surface: shapes, craters, landforms, change over time.","Splits light into colours to tell what a surface is made of.","Measures heat: fires, lava, day-night temperatures, cold traps.","Bounces radio waves off the ground. Sees through cloud, dark and even ice.","Measures heights and gravity, which reveal the inside of a world.","Sniffs out hydrogen, water and other easily-vapourised materials.","Profiles temperature, moisture, gases and storms in an atmosphere.","Senses magnetic fields, charged particles and dust around the spacecraft.","Relays data for other missions. Not science itself, but valuable."];
  this.RoleName = ["Project Manager","Science Lead","Spacecraft Engineer","Comms & Ops Lead"];
  this.RoleShort = ["PM","SCI","ENG","OPS"];
  this.DifficultyName = ["Cadet","Engineer","Chief Engineer"];
  this.BusClassName = ["CubeSat","SmallSat","Medium probe","Flagship"];
  this.Clamp = function (X, Lo, Hi) {
    var Result = 0.0;
    if (X < Lo) {
      Result = Lo}
     else if (X > Hi) {
      Result = Hi}
     else Result = X;
    return Result;
  };
  this.MaxD = function (A, B) {
    var Result = 0.0;
    if (A > B) {
      Result = A}
     else Result = B;
    return Result;
  };
  this.MinD = function (A, B) {
    var Result = 0.0;
    if (A < B) {
      Result = A}
     else Result = B;
    return Result;
  };
  this.AddLine = function (L, AName, AValue) {
    var N = 0;
    N = rtl.length(L.get());
    L.set(rtl.arraySetLength(L.get(),$mod.TLine,N + 1));
    L.get()[N].Name = AName;
    L.get()[N].Value = AValue;
  };
  this.AddStr = function (L, S) {
    var N = 0;
    N = rtl.length(L.get());
    L.set(rtl.arraySetLength(L.get(),"",N + 1));
    L.get()[N] = S;
  };
});
rtl.module("WebUtil",["System","JS","Web","SysUtils"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.El = function (Id) {
    var Result = null;
    Result = document.getElementById(Id);
    return Result;
  };
  this.Esc = function (S) {
    var Result = "";
    Result = pas.SysUtils.StringReplace(S,"&","&amp;",rtl.createSet(0));
    Result = pas.SysUtils.StringReplace(Result,"<","&lt;",rtl.createSet(0));
    Result = pas.SysUtils.StringReplace(Result,">","&gt;",rtl.createSet(0));
    Result = pas.SysUtils.StringReplace(Result,'"',"&quot;",rtl.createSet(0));
    Result = pas.SysUtils.StringReplace(Result,"'","&#39;",rtl.createSet(0));
    return Result;
  };
  this.SetHtml = function (Id, Html) {
    var E = null;
    E = document.getElementById(Id);
    if (E !== null) E.innerHTML = Html;
  };
  this.SetText = function (Id, Txt) {
    var E = null;
    E = document.getElementById(Id);
    if (E !== null) E.textContent = Txt;
  };
  this.Icon = function (Name) {
    var Result = "";
    Result = $impl.IconSvg(Name,"ico");
    return Result;
  };
  this.IconLg = function (Name) {
    var Result = "";
    Result = $impl.IconSvg(Name,"ico ico-lg");
    return Result;
  };
  this.Btn = function (Cls, Act, A, Inner) {
    var Result = "";
    Result = '<button type="button" class="' + Cls + '" data-act="' + Act + '"';
    if (A !== "") Result = Result + ' data-a="' + $mod.Esc(A) + '"';
    Result = Result + ">" + Inner + "</button>";
    return Result;
  };
  this.BtnOff = function (Cls, Inner) {
    var Result = "";
    Result = '<button type="button" class="' + Cls + '" disabled>' + Inner + "</button>";
    return Result;
  };
  this.Chip = function (Cls, Inner) {
    var Result = "";
    Result = '<span class="chip ' + Cls + '">' + Inner + "</span>";
    return Result;
  };
  this.Link = function (Url, Inner) {
    var Result = "";
    Result = '<a href="' + $mod.Esc(Url) + '" target="_blank" rel="noopener noreferrer">' + Inner + "</a>";
    return Result;
  };
  this.NowMs = function () {
    var Result = 0.0;
    Result = Date.now();
    return Result;
  };
  this.TodayIso = function () {
    var Result = "";
    Result = pas.System.Copy((new Date()).toISOString(),1,10);
    return Result;
  };
  this.Toast = function (Msg) {
    var T = null;
    T = $mod.El("toast");
    if (T === null) return;
    T.textContent = Msg;
    T.hidden = false;
    if ($impl.ToastTimer !== 0) window.clearTimeout($impl.ToastTimer);
    $impl.ToastTimer = window.setTimeout(rtl.createSafeCallback($impl,"HideToast"),2600);
  };
  this.ScrollTop = function () {
    window.scrollTo(0,0);
  };
  $mod.$implcode = function () {
    $impl.ToastTimer = 0;
    $impl.IconPath = function (Name) {
      var Result = "";
      if (Name === "check") {
        Result = "M5 13l4 4L19 7"}
       else if (Name === "warn") {
        Result = "M12 3l10 18H2L12 3z M12 10v5 M12 18v.5"}
       else if (Name === "block") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M5 5l14 14"}
       else if (Name === "info") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M12 11v6 M12 7v.5"}
       else if (Name === "rocket") {
        Result = "M12 2c3 2 5 6 5 10l-2 4H9l-2-4c0-4 2-8 5-10z M9 16l-3 4h3 M15 16l3 4h-3 M12 9v.5"}
       else if (Name === "bolt") {
        Result = "M13 2L4 14h7l-1 8 9-12h-7l1-8z"}
       else if (Name === "mass") {
        Result = "M6 8h12l2 13H4L6 8z M9 8a3 3 0 016 0"}
       else if (Name === "coin") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M15 9c-.6-1-1.7-1.5-3-1.5-1.700 0-3 .9-3 2.2 0 3 6 1.500 6 4.300 0 1.300-1.300 2.200-3 2.200-1.400 0-2.500-.6-3-1.600 M12 5.500v2 M12 16.500v2"}
       else if (Name === "data") {
        Result = "M4 6c0-1.700 3.600-3 8-3s8 1.300 8 3-3.600 3-8 3-8-1.300-8-3z M4 6v6c0 1.700 3.600 3 8 3s8-1.300 8-3V6 M4 12v6c0 1.700 3.600 3 8 3s8-1.300 8-3v-6"}
       else if (Name === "dish") {
        Result = "M4 10a8 8 0 0010 10 M4 10l10 10 M9 15l5-5 M16 8a2 2 0 100-4 2 2 0 000 4z"}
       else if (Name === "clock") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M12 6v6l4 2"}
       else if (Name === "flask") {
        Result = "M9 3h6 M10 3v6l-5 10a1 1 0 001 2h12a1 1 0 001-2l-5-10V3"}
       else if (Name === "shield") {
        Result = "M12 2l8 3v6c0 5-3.500 9-8 11-4.500-2-8-6-8-11V5l8-3z"}
       else if (Name === "users") {
        Result = "M8 11a3.500 3.500 0 100-7 3.500 3.500 0 000 7z M2 20c0-3.300 2.700-6 6-6s6 2.700 6 6 M17 11a3 3 0 100-6 M22 20c0-2.800-2-5-4.500-5.700"}
       else if (Name === "book") {
        Result = "M4 4h7a3 3 0 013 3v13a2 2 0 00-2-2H4V4z M20 4h-3a3 3 0 00-3 3"}
       else if (Name === "play") {
        Result = "M7 4l13 8-13 8V4z"}
       else if (Name === "pause") {
        Result = "M7 4h3v16H7z M14 4h3v16h-3z"}
       else if (Name === "skip") {
        Result = "M5 4l10 8-10 8V4z M18 4v16"}
       else if (Name === "share") {
        Result = "M4 12v7h16v-7 M12 3v12 M8 7l4-4 4 4"}
       else if (Name === "back") {
        Result = "M15 5l-7 7 7 7"}
       else if (Name === "next") {
        Result = "M9 5l7 7-7 7"}
       else if (Name === "orbit") {
        Result = "M12 9a3 3 0 100 6 3 3 0 000-6z M3 12c0-2.500 4-4.500 9-4.500s9 2 9 4.500-4 4.500-9 4.500-9-2-9-4.500z"}
       else if (Name === "sun") {
        Result = "M12 8a4 4 0 100 8 4 4 0 000-8z M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M19 5l-2 2 M7 17l-2 2"}
       else if (Name === "cpu") {
        Result = "M7 7h10v10H7z M10 2v5 M14 2v5 M10 17v5 M14 17v5 M2 10h5 M2 14h5 M17 10h5 M17 14h5"}
       else if (Name === "target") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M12 7a5 5 0 100 10 5 5 0 000-10z M12 11.500v1"}
       else if (Name === "star") {
        Result = "M12 3l2.700 5.600 6.100.9-4.400 4.300 1 6.100L12 17l-5.400 2.900 1-6.100-4.400-4.300 6.100-.9L12 3z"}
       else if (Name === "x") {
        Result = "M6 6l12 12 M18 6L6 18"}
       else if (Name === "flag") {
        Result = "M5 21V4 M5 4h12l-2 4 2 4H5"}
       else if (Name === "globe") {
        Result = "M12 2a10 10 0 100 20 10 10 0 000-20z M2 12h20 M12 2c3 3 3 17 0 20 M12 2c-3 3-3 17 0 20"}
       else if (Name === "trophy") {
        Result = "M7 4h10v5a5 5 0 01-10 0V4z M7 6H4c0 3 1.500 4.500 3.500 4.500 M17 6h3c0 3-1.500 4.500-3.500 4.500 M12 14v4 M8 21h8"}
       else if (Name === "list") {
        Result = "M8 6h13 M8 12h13 M8 18h13 M3 6h.5 M3 12h.5 M3 18h.5"}
       else if (Name === "redo") {
        Result = "M20 11a8 8 0 10-2.300 5.700 M20 4v7h-7"}
       else if (Name === "wrench") {
        Result = "M14 6a4 4 0 005 5l-9 9a2.100 2.100 0 01-3-3l9-9a4 4 0 00-2-2z"}
       else Result = "M12 2a10 10 0 100 20 10 10 0 000-20z";
      return Result;
    };
    $impl.IconSvg = function (Name, Cls) {
      var Result = "";
      Result = '<svg class="' + Cls + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' + 'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + $impl.IconPath(Name) + '"/></svg>';
      return Result;
    };
    $impl.HideToast = function () {
      var T = null;
      T = $mod.El("toast");
      if (T !== null) T.hidden = true;
    };
  };
},[]);
rtl.module("TsCatalog",["System","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.Instruments = [];
  this.Parts = rtl.arraySetLength(null,[],12);
  this.Launchers = [];
  this.Glossary = [];
  this.PartKindOwner = [2,2,2,2,3,2,3,3,3,3,0,0];
  this.MV = function (Im, Sp, Th, Ra, Tp, Vo, At, Fi, Se) {
    var Result = rtl.arraySetLength(null,0.0,9);
    Result[0] = Im;
    Result[1] = Sp;
    Result[2] = Th;
    Result[3] = Ra;
    Result[4] = Tp;
    Result[5] = Vo;
    Result[6] = At;
    Result[7] = Fi;
    Result[8] = Se;
    return Result;
  };
  this.FindInstrument = function (AId) {
    var Result = 0;
    var I = 0;
    Result = -1;
    for (var $l = 0, $end = rtl.length($mod.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if ($mod.Instruments[I].Id === AId) {
        Result = I;
        return Result;
      };
    };
    return Result;
  };
  this.FindPart = function (AKind, AId) {
    var Result = 0;
    var I = 0;
    Result = -1;
    for (var $l = 0, $end = rtl.length($mod.Parts[AKind]) - 1; $l <= $end; $l++) {
      I = $l;
      if ($mod.Parts[AKind][I].Id === AId) {
        Result = I;
        return Result;
      };
    };
    return Result;
  };
  this.FindLauncher = function (AId) {
    var Result = 0;
    var I = 0;
    Result = -1;
    for (var $l = 0, $end = rtl.length($mod.Launchers) - 1; $l <= $end; $l++) {
      I = $l;
      if ($mod.Launchers[I].Id === AId) {
        Result = I;
        return Result;
      };
    };
    return Result;
  };
  this.BusClassOf = function (P) {
    var Result = 0;
    var $tmp = P.Tier;
    if ($tmp === 0) {
      Result = 0}
     else if ($tmp === 1) {
      Result = 1}
     else if ($tmp === 2) {
      Result = 2}
     else {
      Result = 3;
    };
    return Result;
  };
  $mod.$implcode = function () {
    $impl.AddInstr = function (AId, AName, AAnalog, ABlurb, AMass, APower, ACost, AData, ADuty, ADev, AValue, AFine, ACool, AHga, AMinBus) {
      var N = 0;
      N = rtl.length($mod.Instruments);
      $mod.Instruments = rtl.arraySetLength($mod.Instruments,pas.TsTypes.TInstrument,N + 1);
      $mod.Instruments[N].Id = AId;
      $mod.Instruments[N].Name = AName;
      $mod.Instruments[N].Analog = AAnalog;
      $mod.Instruments[N].Blurb = ABlurb;
      $mod.Instruments[N].MassKg = AMass;
      $mod.Instruments[N].PowerW = APower;
      $mod.Instruments[N].CostM = ACost;
      $mod.Instruments[N].DataMbps = AData;
      $mod.Instruments[N].Duty = ADuty;
      $mod.Instruments[N].DevYears = ADev;
      $mod.Instruments[N].Value = AValue.slice(0);
      $mod.Instruments[N].NeedsFinePointing = AFine;
      $mod.Instruments[N].NeedsCooling = ACool;
      $mod.Instruments[N].NeedsHGA = AHga;
      $mod.Instruments[N].MinBus = AMinBus;
    };
    $impl.AddPart = function (AKind, AId, AName, AAnalog, ABlurb, AMass, APower, ACost, ADev, ATier, AMinBus, A, B, C, D, E, F, G) {
      var N = 0;
      N = rtl.length($mod.Parts[AKind]);
      $mod.Parts[AKind] = rtl.arraySetLength($mod.Parts[AKind],pas.TsTypes.TPart,N + 1);
      $mod.Parts[AKind][N].Kind = AKind;
      $mod.Parts[AKind][N].Id = AId;
      $mod.Parts[AKind][N].Name = AName;
      $mod.Parts[AKind][N].Analog = AAnalog;
      $mod.Parts[AKind][N].Blurb = ABlurb;
      $mod.Parts[AKind][N].MassKg = AMass;
      $mod.Parts[AKind][N].PowerW = APower;
      $mod.Parts[AKind][N].CostM = ACost;
      $mod.Parts[AKind][N].DevYears = ADev;
      $mod.Parts[AKind][N].Tier = ATier;
      $mod.Parts[AKind][N].MinBus = AMinBus;
      $mod.Parts[AKind][N].A = A;
      $mod.Parts[AKind][N].B = B;
      $mod.Parts[AKind][N].C = C;
      $mod.Parts[AKind][N].D = D;
      $mod.Parts[AKind][N].E = E;
      $mod.Parts[AKind][N].F = F;
      $mod.Parts[AKind][N].G = G;
    };
    $impl.AddLauncher = function (AId, AName, AAgency, ABlurb, ALeo, ASso, AGto, AC3Zero, AC3K, ACost, ARel, AMaxBus, ARideshare, ASize) {
      var N = 0;
      N = rtl.length($mod.Launchers);
      $mod.Launchers = rtl.arraySetLength($mod.Launchers,pas.TsTypes.TLauncher,N + 1);
      $mod.Launchers[N].Id = AId;
      $mod.Launchers[N].Name = AName;
      $mod.Launchers[N].Agency = AAgency;
      $mod.Launchers[N].Blurb = ABlurb;
      $mod.Launchers[N].LeoKg = ALeo;
      $mod.Launchers[N].SsoKg = ASso;
      $mod.Launchers[N].GtoKg = AGto;
      $mod.Launchers[N].C3ZeroKg = AC3Zero;
      $mod.Launchers[N].C3K = AC3K;
      $mod.Launchers[N].CostM = ACost;
      $mod.Launchers[N].Reliability = ARel;
      $mod.Launchers[N].MaxBus = AMaxBus;
      $mod.Launchers[N].Rideshare = ARideshare;
      $mod.Launchers[N].Size = ASize;
    };
    $impl.AddTerm = function (ATerm, APlain, AWhy) {
      var N = 0;
      N = rtl.length($mod.Glossary);
      $mod.Glossary = rtl.arraySetLength($mod.Glossary,pas.TsTypes.TGlossaryItem,N + 1);
      $mod.Glossary[N].Term = ATerm;
      $mod.Glossary[N].Plain = APlain;
      $mod.Glossary[N].Why = AWhy;
    };
    $impl.BuildInstruments = function () {
      $impl.AddInstr("cam_ctx","Wide-angle context camera","Like CTX on Mars Reconnaissance Orbiter","A small, sturdy camera that maps wide areas. Light and cheap, modest detail.",4,7,6,3,0.35,0.15,$mod.MV(35,0,0,0,0,0,0,0,0),false,false,false,0);
      $impl.AddInstr("cam_hires","High-resolution telescope camera","Like HiRISE on Mars Reconnaissance Orbiter","A telescope with a camera on the end. Stunning detail, but heavy, data-hungry and it needs a very steady spacecraft.",48,60,40,24,0.15,0.4,$mod.MV(85,0,0,0,15,0,0,0,0),true,false,false,1);
      $impl.AddInstr("spec_vnir","Imaging spectrometer","Like M3, which found water on the Moon from Chandrayaan-1","Splits reflected sunlight into hundreds of colours to identify minerals and ices. Its detector must be kept very cold.",16,38,24,8,0.3,0.3,$mod.MV(10,75,0,0,0,25,0,0,0),false,true,false,1);
      $impl.AddInstr("tir","Thermal infrared imager","Like Diviner on Lunar Reconnaissance Orbiter","Maps temperature. Spots fires and lava on Earth, cold traps on the Moon and warm ice on Europa.",9,20,13,1.2,0.5,0.2,$mod.MV(0,0,75,0,0,10,0,0,0),false,false,false,0);
      $impl.AddInstr("sar","Imaging radar and sounder","Like Mini-RF on LRO, SHARAD on MRO and REASON on Europa Clipper","Makes its own radio light, so it sees through cloud, darkness and ice. Very power-hungry and produces floods of data.",30,150,38,30,0.12,0.4,$mod.MV(0,0,0,85,10,20,0,0,0),false,false,false,1);
      $impl.AddInstr("lidar","Laser altimeter","Like LOLA on LRO; OSIRIS-REx carried one from the Canadian Space Agency","Fires laser pulses at the ground and times the echo to build a 3D map. Works best from a low orbit.",13,34,19,0.05,0.9,0.25,$mod.MV(0,0,0,0,80,0,0,0,0),false,false,false,1);
      $impl.AddInstr("neutron","Neutron spectrometer","Like the one on Lunar Prospector that first hinted at polar ice","Counts neutrons leaking from the ground. Fewer neutrons means hydrogen, and hydrogen usually means water ice. Only works close to the surface.",5,8,8,0.002,1.0,0.15,$mod.MV(0,0,0,0,0,75,0,0,0),false,false,false,0);
      $impl.AddInstr("mag","Magnetometer on a boom","Like the magnetometers on MAVEN, Juno and Europa Clipper","Measures magnetic fields. At Europa, a wobbling field revealed a salty ocean hidden under the ice.",3,4,5,0.004,1.0,0.1,$mod.MV(0,0,0,0,15,0,0,50,0),false,false,false,0);
      $impl.AddInstr("plasma","Plasma and particle suite","Like the particle instruments on MAVEN and ESCAPADE","Tastes the thin, electrically charged gas around the spacecraft and shows how a world loses its air.",11,14,15,0.02,1.0,0.2,$mod.MV(0,0,0,0,0,0,20,65,0),false,false,false,1);
      $impl.AddInstr("massspec","Mass spectrometer","Like NGIMS on MAVEN and MASPEX on Europa Clipper","Weighs individual molecules to say exactly which gases are present. It has to fly through the gas it studies.",14,28,27,0.01,0.3,0.3,$mod.MV(0,0,0,0,0,45,55,0,0),false,false,false,1);
      $impl.AddInstr("radiometer","Microwave radiometer","Like the TROPICS storm-watching CubeSats and Mars Climate Sounder","Reads temperature and moisture inside clouds and atmospheres. Small enough for a CubeSat.",6,12,10,0.06,1.0,0.15,$mod.MV(0,0,10,0,0,0,75,0,0),false,false,false,0);
      $impl.AddInstr("uvs","Ultraviolet spectrometer","Like LAMP on LRO, which peers into permanently dark craters","Watches faint ultraviolet glow from thin gases, plumes and frost.",7,9,11,0.3,0.5,0.2,$mod.MV(0,25,0,0,0,20,45,0,0),false,false,false,0);
      $impl.AddInstr("dust","Dust analyser","Like LDEX on LADEE and SUDA on Europa Clipper","Catches tiny grains knocked off the surface and reads their chemistry, sampling the ground without landing.",6,8,10,0.01,1.0,0.2,$mod.MV(0,10,0,0,0,35,0,30,0),false,false,false,0);
      $impl.AddInstr("radio","Radio science package","Gravity science as on GRAIL, Juno and MRO","An ultra-stable clock for the radio. Tiny changes in the signal reveal the gravity, and so the inside, of a world. Needs a dish antenna.",2,3,3,0,1.0,0.05,$mod.MV(0,0,0,0,45,0,0,0,0),false,false,true,0);
      $impl.AddInstr("relay","UHF relay radio","Like Electra on MRO and MAVEN","Passes messages between Earth and landers or rovers on the surface. No science of its own, but other missions depend on it.",5,18,8,0,0.2,0.1,$mod.MV(0,0,0,0,0,0,0,0,80),false,false,false,1);
    };
    $impl.BuildParts = function () {
      $impl.AddPart(0,"cube","12U CubeSat","Like CAPSTONE and the MarCO pair","The size of a large shoebox. Cheap and fast to build, but there is room for only one or two small instruments.",5,6,2.5,1.2,0,0,36,10,2,1.5,1.2,0.72,0.15);
      $impl.AddPart(0,"small","SmallSat (ESPA class)","Like Lunar Trailblazer and ESCAPADE","About the size of a washing machine. A good balance for focused missions on a budget.",48,30,16,2.2,1,1,380,90,4,10,3.5,0.80,1.0);
      $impl.AddPart(0,"medium","Medium probe (Discovery class)","Like MAVEN and Lunar Reconnaissance Orbiter","A car-sized spacecraft that can carry a full instrument suite and a big antenna.",240,110,105,3.5,2,2,1900,280,7,50,13,0.86,3.2);
      $impl.AddPart(0,"large","Flagship bus","Like Europa Clipper and Cassini","A bus-sized spacecraft. Carries everything, costs a fortune and takes most of a decade to build.",720,280,360,5.5,3,3,5200,850,12,130,38,0.90,7.0);
      $impl.AddPart(1,"none","No propulsion","Many Earth-orbit CubeSats","No engine at all. Nothing to leak or explode, but the spacecraft can never change its orbit.",0,0,0,0,0,0,0,0,0,1,0,0,0);
      $impl.AddPart(1,"cold","Cold-gas thrusters","Used on small CubeSats","Puffs of compressed gas. Simple and safe, but far too weak for big manoeuvres.",1.5,0,0.8,0,1,0,65,0.25,0,0.995,0.004,0,0);
      $impl.AddPart(1,"mono","Monopropellant thrusters","Hydrazine, as on most spacecraft","One liquid sprayed over a catalyst. Reliable workhorse for steering and small orbit changes.",6,0,3,0,2,0,225,0.12,0,0.99,0.012,0,0);
      $impl.AddPart(1,"biprop","Bipropellant main engine","As on MRO, Juno and Europa Clipper","Fuel plus oxidiser. About 40 % more push per kilogram, which matters enormously for braking into orbit.",28,0,12,0,3,1,320,0.10,0,0.985,0.015,0,0);
      $impl.AddPart(1,"sep","Solar electric propulsion","As on Dawn, Psyche, Hayabusa2 and SMART-1","Ion engines sip xenon and are six times more efficient, but push as gently as a sheet of paper and need a lot of electricity. Trips take longer.",30,0,22,0.5,4,0,1800,0.12,900,0.99,0.02,0,0);
      $impl.AddPart(2,"mtq","Magnetorquers and sun sensors","Common on Earth-orbit CubeSats","Electromagnets that push against Earth's magnetic field. Coarse pointing, and useless anywhere without a strong magnetic field.",1.5,2,0.5,0,0,0,1,0,0,0,0,0,0);
      $impl.AddPart(2,"rw3","Reaction wheels and star tracker","Standard on most science spacecraft","Three spinning wheels turn the spacecraft precisely. If one wheel fails, fine pointing is lost.",9,16,4.5,0,1,0,0,0,0,0,0,0,0);
      $impl.AddPart(2,"rw4","Four wheels, twin star trackers","As on Kepler, MRO and Europa Clipper","A spare wheel and a second star tracker. Rock-steady pointing that survives a failure.",14,24,9,0.1,2,0,0,1,0,0,0,0,0);
      $impl.AddPart(3,"passive","Passive: blankets and heaters","Used on simple spacecraft","Shiny insulation, paint and a few heaters. Light and cheap. Fine in gentle environments.",0,0,0.6,0,0,0,0.02,1.0,0,0,0,0,0);
      $impl.AddPart(3,"active","Active: louvres, heat pipes, radiators","As on Juno and MRO","Moves heat to where it is needed and dumps the rest. Needed for extreme cold or heat and for power-hungry equipment.",0,0,2.5,0.1,1,0,0.04,0.6,0,0,0,0,0);
      $impl.AddPart(3,"cryo","Active plus cryocooler","As on infrared space telescopes","Adds a mechanical fridge that keeps infrared detectors far below freezing. Extra mass, power and cost.",8,45,2.5,0.3,2,1,0.045,0.6,0,0,12,0,0);
      $impl.AddPart(4,"cots","Commercial computer","Phone-class parts, used on CubeSats","Fast and cheap, with 8 GB of storage. Not built for radiation: happy in low Earth orbit, fragile beyond it.",0.6,5,0.6,0,0,0,64,0,0,0,0,0,0);
      $impl.AddPart(4,"radtol","Radiation-tolerant computer","As on many SmallSat missions","Hardened against most radiation upsets, with 64 GB of storage. A sensible middle path.",2,12,4,0,1,0,512,0,0,0,0,0,0);
      $impl.AddPart(4,"radhard","Radiation-hardened computer and recorder","RAD750 heritage: MRO, Juno, Perseverance","Slow but nearly indestructible, with a 250 GB solid-state recorder. The choice for deep space.",9,28,15,0.1,2,1,2000,0,0,0,0,0,0);
      $impl.AddPart(5,"none","No extra shielding","Typical in low Earth orbit","Relies on the parts themselves. Saves mass.",0,0,0,0,0,0,0,0,0,0,0,0,0);
      $impl.AddPart(5,"spot","Spot shielding","Metal covers on sensitive chips","Small slabs of metal over the most delicate electronics.",3,0,1.5,0,1,0,0,0,0,0,0,0,0);
      $impl.AddPart(5,"vault","Radiation vault","Juno's 200 kg titanium vault","A thick-walled metal box around all the electronics. Heavy, but the only way to survive the worst radiation belts.",28,0,6,0.2,2,1,0,0,0,0,0,0,0);
      $impl.AddPart(6,"patch","Patch antenna","A flat plate the size of a coaster","Radiates in almost every direction, so it never needs pointing, but very little of the signal reaches Earth.",0.2,0,0.2,0,0,0,0.03,0,0,0,0,0,0);
      $impl.AddPart(6,"dish06","0.6 m dish or reflectarray","MarCO's fold-out panel","A small dish focuses the signal into a beam. It must be pointed at Earth.",2.5,0,1.5,0,1,0,0.6,0,0,0,0,0,0);
      $impl.AddPart(6,"dish12","1.2 m dish","Typical SmallSat high-gain antenna","Four times the collecting area of the 0.6 m dish, so four times the data rate.",8,0,3.5,0,2,1,1.2,0,0,0,0,0,0);
      $impl.AddPart(6,"dish20","2 m dish","MAVEN and Juno class","A serious deep-space antenna. Needs a medium-sized spacecraft to carry it.",19,0,7,0,3,2,2.0,0,0,0,0,0,0);
      $impl.AddPart(6,"dish30","3 m dish","Mars Reconnaissance Orbiter, Europa Clipper","The big one. MRO's 3 m dish has returned more data than every other planetary mission combined.",36,0,12,0.1,4,2,3.0,0,0,0,0,0,0);
      $impl.AddPart(7,"uhf","UHF","Amateur-radio style, used by CubeSats near Earth","Simple and cheap, a trickle of data. Cannot reach Earth from deep space.",0.4,4,0.3,0,0,0,0.003,1,1.0,0,0,0,0);
      $impl.AddPart(7,"s","S-band","Classic telemetry and command band","Reliable in any weather. Fine for commands and small amounts of data.",1.5,5,1.0,0,1,0,0.07,5,1.0,0,0,0,0);
      $impl.AddPart(7,"x","X-band","The standard for deep space","A higher frequency packs the signal into a tighter beam: about 14 times the data of S-band from the same dish.",2.2,8,3.5,0,2,0,1.0,150,1.0,0,0,0,0);
      $impl.AddPart(7,"ka","Ka-band","Used by LRO, Kepler and JWST","Tighter beam again, four times the data of X-band. Rain on Earth can block it and the dish must be pointed precisely.",5,10,7,0.1,3,1,4.0,800,0.9,1,0,0,0);
      $impl.AddPart(7,"opt","Laser communications","Demonstrated by DSOC on Psyche and LCRD","Sends data on a laser beam: tens of times faster than radio. Clouds block it and it demands extremely steady pointing.",28,80,42,0.75,4,1,60,2000,0.65,2,0,0,0);
      $impl.AddPart(8,"tx5","5 W transmitter","Solid-state amplifier","About the power of a bicycle lamp. Enough close to Earth.",0.6,22,0.5,0,0,0,5,0,0,0,0,0,0);
      $impl.AddPart(8,"tx20","20 W transmitter","Solid-state amplifier","Four times the signal, and four times the data, for 70 W of electricity.",2,70,1.8,0,1,0,20,0,0,0,0,0,0);
      $impl.AddPart(8,"tx100","100 W travelling-wave tube","As on Mars Reconnaissance Orbiter","The loudest voice available. Drinks over 200 W while transmitting.",6.5,210,6,0,2,1,100,0,0,0,0,0,0);
      $impl.AddPart(9,"basic","Basic: one short contact a day","A shared 34 m dish","The cheapest plan. Around 2 hours a day in deep space, or a couple of passes a day in low Earth orbit.",0,0,0.8,0,0,0,2,0.3,1.0,0,0,0,0);
      $impl.AddPart(9,"standard","Standard: daily 8-hour track","A normal Deep Space Network schedule","One full shift of listening per day, or half a dozen passes a day near Earth.",0,0,3.5,0,1,0,8,0.9,1.0,0,0,0,0);
      $impl.AddPart(9,"premium","Premium: 70 m dishes, long tracks","Priority time on the biggest antennas","Fourteen hours a day on the 70 m giants, which hear four times fainter signals. Near Earth, a station on every orbit.",0,0,11,0,2,0,14,2.2,4.2,0,0,0,0);
      $impl.AddPart(10,"classd","Class D: lean and single-string","Lunar Trailblazer, most CubeSats","Commercial parts, one of everything, light testing. About 20 % cheaper and faster, but failures are more than twice as likely.",0,0,0,-0.4,0,0,0.80,0.95,2.2,-0.4,0,0,0);
      $impl.AddPart(10,"classc","Class C: selective backups","Many Discovery-class missions","Spares for the things most likely to fail, and thorough testing.",0,0,0,0,1,0,1.0,1.0,1.0,0,0,0,0);
      $impl.AddPart(10,"classb","Class B: fully redundant","Flagships such as Europa Clipper","Two of everything important and exhaustive testing. A third more cost, more mass and time, but less than half the failures.",0,0,0,0.8,2,0,1.35,1.15,0.45,0.8,0,0,0);
      $impl.AddPart(11,"standard","Standard schedule","A normal development pace","Enough time to design, build and test properly.",0,0,0,0,0,0,1.0,1.0,1.0,0,0,0,0);
      $impl.AddPart(11,"fast","Accelerated schedule","Around-the-clock shifts, parallel work","A quarter less time for about 18 % more money. Less testing means more risk.",0,0,0,0,1,0,0.75,1.18,1.35,0,0,0,0);
    };
    $impl.BuildLaunchers = function () {
      $impl.AddLauncher("rideshare","Rideshare slot","Commercial rideshare","A seat on someone else's rocket. By far the cheapest way up, but you go where and when the main passenger goes.",0,350,0,450,100000,1.2,0.985,1,true,1);
      $impl.AddLauncher("electron","Electron","Rocket Lab (USA / New Zealand)","A small dedicated rocket. With its kick stage it sent the 25 kg CAPSTONE CubeSat to the Moon.",300,200,0,55,14,8,0.93,1,false,0);
      $impl.AddLauncher("alpha","Firefly Alpha","Firefly Aerospace (USA)","A one-tonne-class small launcher with a short flight record.",1030,630,0,0,1,15.5,0.86,1,false,0);
      $impl.AddLauncher("pslv","PSLV-XL","ISRO (India)","India's workhorse. It launched Chandrayaan-1 to the Moon and Mangalyaan to Mars.",3800,1750,1425,500,18,30,0.95,2,false,1);
      $impl.AddLauncher("vegac","Vega-C","ESA / Italy","Europe's light launcher, built for polar Earth-observation satellites.",3300,2250,0,0,1,42,0.90,2,false,1);
      $impl.AddLauncher("lvm3","LVM3","ISRO (India)","India's heavy lifter. It sent Chandrayaan-3 on its way to the Moon.",8000,6000,4000,2300,30,52,0.97,3,false,2);
      $impl.AddLauncher("h3","H3","JAXA (Japan)","Japan's new flagship rocket, chosen to launch the MMX mission to the moons of Mars.",6500,4000,6500,3600,42,55,0.93,3,false,2);
      $impl.AddLauncher("falcon9","Falcon 9","SpaceX (USA)","The most-flown rocket in the world, with a reusable first stage. Launched DART, TESS and IXPE for NASA.",17500,11000,5500,3400,38,70,0.99,3,false,2);
      $impl.AddLauncher("ariane64","Ariane 64","ESA / ArianeGroup (Europe)","Europe's heavy launcher with four boosters.",21650,15500,11500,7400,46,125,0.96,3,false,3);
      $impl.AddLauncher("vulcan","Vulcan Centaur","United Launch Alliance (USA)","Successor to the Atlas V that launched MRO, MAVEN, LRO, Juno and OSIRIS-REx. Its Centaur upper stage excels at high-energy escapes.",24600,20000,11300,8500,52,135,0.96,3,false,3);
      $impl.AddLauncher("falconheavy","Falcon Heavy (expendable)","SpaceX (USA)","Three Falcon 9 cores strapped together. Launched Psyche and Europa Clipper.",63800,45000,26700,15000,45,150,0.985,3,false,3);
      $impl.AddLauncher("sls","Space Launch System","NASA (USA)","The Moon rocket. It can throw a spacecraft straight to Jupiter, at a price that swallows most budgets whole.",95000,0,40000,26000,48,2200,0.97,3,false,3);
    };
    $impl.BuildGlossary = function () {
      $impl.AddTerm("Payload","The science instruments: the reason the mission exists.","Everything else on the spacecraft is there to carry, power, point and talk for the payload.");
      $impl.AddTerm("Bus","The spacecraft body and all its support systems.","A bigger bus carries more instruments, but needs more fuel and a bigger rocket.");
      $impl.AddTerm("Trade study","Comparing options by what each one costs and gains.","There is rarely one right answer. Good teams compare several designs before choosing.");
      $impl.AddTerm("Mass margin","Spare lifting capacity between your spacecraft and what the rocket can carry.","Spacecraft almost always gain weight while being built. NASA teams start with 25 to 30 % in hand.");
      $impl.AddTerm("Power margin","Spare electricity beyond what the spacecraft needs.","Solar panels fade and instruments draw more than planned. Without margin, something has to be switched off.");
      $impl.AddTerm("Delta-v","The total change in speed a spacecraft can make with its engines.","Every manoeuvre, from braking into orbit to staying there, spends delta-v. When it is gone, the mission is over.");
      $impl.AddTerm("Rocket equation","The rule that fuel needs fuel to carry it.","Doubling the speed change needs far more than double the propellant. This is why spacecraft are mostly fuel tank.");
      $impl.AddTerm("Specific impulse","How much push an engine gets from each kilogram of propellant.","Higher is better. Chemical engines reach about 320 seconds, ion engines about 1,800 or more.");
      $impl.AddTerm("Launch energy (C3)","How hard the rocket must throw the spacecraft to escape Earth.","The higher the energy, the less mass a rocket can send. Far-off worlds need a bigger rocket or a slower route.");
      $impl.AddTerm("Launch window","The dates when the planets line up for the trip.","For Mars it opens for a few weeks every 26 months. Miss it and you wait.");
      $impl.AddTerm("Gravity assist","Stealing speed from a planet by flying close past it.","It saves launch energy, so a smaller rocket will do, but adds years to the journey.");
      $impl.AddTerm("Aerobraking","Dipping into the top of an atmosphere to slow down for free.","It saves hundreds of kilograms of fuel but takes months of careful flying.");
      $impl.AddTerm("Inclination","How steeply an orbit is tilted from the equator.","A spacecraft can only fly over latitudes up to its inclination. To see the poles you need a polar orbit.");
      $impl.AddTerm("Sun-synchronous orbit","A near-polar orbit that passes over each place at the same local time of day.","The lighting is always the same, so pictures from different days can be compared.");
      $impl.AddTerm("Geostationary orbit","An orbit 35,786 km up where a satellite keeps pace with Earth's rotation.","It stares at the same third of the planet all the time, but from far away, so detail is poor.");
      $impl.AddTerm("Eclipse","The part of each orbit spent in the shadow of a planet or moon.","Solar panels make nothing in shadow, so the battery has to carry the whole spacecraft.");
      $impl.AddTerm("RTG","A nuclear battery that turns the heat of decaying plutonium into electricity.","It works anywhere, even far from the Sun, but is heavy, scarce and very expensive.");
      $impl.AddTerm("Data rate","How many bits per second the spacecraft can send home.","It falls with the square of distance. Twice as far means a quarter of the data.");
      $impl.AddTerm("Deep Space Network","NASA's giant dish antennas in California, Spain and Australia.","Every deep-space mission shares them, so listening time is rationed and costs money.");
      $impl.AddTerm("Light-time delay","How long a radio signal takes to cross the distance.","About 1.3 seconds to the Moon, up to 22 minutes to Mars, around 45 minutes to Jupiter. The spacecraft must look after itself.");
      $impl.AddTerm("Attitude control","How a spacecraft knows which way it faces and turns to point.","Sharp cameras and narrow radio beams need steady pointing. Coarse pointing blurs both.");
      $impl.AddTerm("Radiation","High-energy particles from the Sun, deep space and planetary radiation belts.","They scramble and slowly destroy electronics. Jupiter's belts are the harshest in the solar system.");
      $impl.AddTerm("Safe mode","A protective state: instruments off, panels to the Sun, wait for help.","It saves the spacecraft, but every day in safe mode is a day without science.");
      $impl.AddTerm("Risk class","NASA grades missions from A (must not fail) to D (cheap, higher risk accepted).","More backups and testing cost money, mass and time. The right level depends on what you can afford to lose.");
      $impl.AddTerm("Reserves","Money set aside for problems nobody has thought of yet.","Problems always appear. NASA expects about 25 % in reserve when a mission is confirmed.");
      $impl.AddTerm("Threshold and baseline science","The minimum result that still counts as success, and the full result you are aiming for.","Knowing the minimum tells a team what can be cut when trouble comes.");
      $impl.AddTerm("Concept Maturity Level","NASA JPL's scale for how well thought-out a mission idea is, from a sketch (1) to a full point design (4) and beyond.","This game walks an idea up that ladder: objective, trade space, point design, review.");
    };
  };
  $mod.$init = function () {
    $impl.BuildInstruments();
    $impl.BuildParts();
    $impl.BuildLaunchers();
    $impl.BuildGlossary();
  };
},[]);
rtl.module("TsFmt",["System"],function () {
  "use strict";
  var $mod = this;
  this.FmtNum = function (X, Dec) {
    var Result = "";
    var Neg = false;
    var Scale = 0.0;
    var V = 0;
    var IntV = 0;
    var FracV = 0;
    var ScaleI = 0;
    var S = "";
    var FracS = "";
    var I = 0;
    var Cnt = 0;
    Neg = X < 0;
    if (Neg) X = -X;
    Scale = 1;
    for (var $l = 1, $end = Dec; $l <= $end; $l++) {
      I = $l;
      Scale = Scale * 10;
    };
    ScaleI = pas.System.Trunc(Scale);
    V = pas.System.Trunc((X * Scale) + 0.5);
    IntV = rtl.trunc(V / ScaleI);
    FracV = V % ScaleI;
    S = pas.SysUtils.IntToStr(IntV);
    Result = "";
    Cnt = 0;
    for (var $l1 = S.length; $l1 >= 1; $l1--) {
      I = $l1;
      Result = S.charAt(I - 1) + Result;
      Cnt += 1;
      if (((Cnt % 3) === 0) && (I > 1)) Result = "," + Result;
    };
    if (Dec > 0) {
      FracS = pas.SysUtils.IntToStr(FracV);
      while (FracS.length < Dec) FracS = "0" + FracS;
      Result = Result + "." + FracS;
    };
    if (Neg && (V !== 0)) Result = "-" + Result;
    return Result;
  };
  this.FmtAuto = function (X) {
    var Result = "";
    var A = 0.0;
    A = Math.abs(X);
    if (A >= 100) {
      Result = $mod.FmtNum(X,0)}
     else if (A >= 10) {
      Result = $mod.FmtNum(X,1)}
     else if (A >= 1) {
      Result = $mod.FmtNum(X,2)}
     else Result = $mod.FmtNum(X,3);
    return Result;
  };
  this.FmtMoney = function (M) {
    var Result = "";
    var A = 0.0;
    A = Math.abs(M);
    if (A >= 1000) {
      Result = "$" + $mod.FmtNum(M / 1000,2) + "B"}
     else if (A >= 100) {
      Result = "$" + $mod.FmtNum(M,0) + "M"}
     else Result = "$" + $mod.FmtNum(M,1) + "M";
    return Result;
  };
  this.FmtMass = function (Kg) {
    var Result = "";
    var A = 0.0;
    A = Math.abs(Kg);
    if (A >= 10000) {
      Result = $mod.FmtNum(Kg / 1000,1) + " t"}
     else if (A >= 100) {
      Result = $mod.FmtNum(Kg,0) + " kg"}
     else Result = $mod.FmtNum(Kg,1) + " kg";
    return Result;
  };
  this.FmtPower = function (W) {
    var Result = "";
    var A = 0.0;
    A = Math.abs(W);
    if (A >= 10000) {
      Result = $mod.FmtNum(W / 1000,1) + " kW"}
     else if (A >= 100) {
      Result = $mod.FmtNum(W,0) + " W"}
     else Result = $mod.FmtNum(W,1) + " W";
    return Result;
  };
  this.FmtPct = function (Fraction) {
    var Result = "";
    Result = $mod.FmtNum(Fraction * 100,0) + "%";
    return Result;
  };
  this.FmtSignedPct = function (Fraction) {
    var Result = "";
    if (Fraction >= 0) {
      Result = "+" + $mod.FmtNum(Fraction * 100,0) + "%"}
     else Result = $mod.FmtNum(Fraction * 100,0) + "%";
    return Result;
  };
  this.FmtYears = function (Y) {
    var Result = "";
    if (Y < 0.095) {
      Result = $mod.FmtNum(Y * 365.25,0) + " days"}
     else if (Y < 1) {
      Result = $mod.FmtNum(Y * 12,0) + " months"}
     else Result = $mod.FmtNum(Y,1) + " years";
    return Result;
  };
  this.FmtRate = function (Mbps) {
    var Result = "";
    if (Mbps >= 1000) {
      Result = $mod.FmtNum(Mbps / 1000,1) + " Gbps"}
     else if (Mbps >= 1) {
      Result = $mod.FmtAuto(Mbps) + " Mbps"}
     else if (Mbps >= 0.001) {
      Result = $mod.FmtAuto(Mbps * 1000) + " kbps"}
     else Result = $mod.FmtNum(Mbps * 1000000,0) + " bps";
    return Result;
  };
  this.FmtData = function (Gbit) {
    var Result = "";
    var GB = 0.0;
    GB = Gbit / 8;
    if (GB >= 1000) {
      Result = $mod.FmtAuto(GB / 1000) + " TB"}
     else if (GB >= 1) {
      Result = $mod.FmtAuto(GB) + " GB"}
     else if (GB >= 0.001) {
      Result = $mod.FmtAuto(GB * 1000) + " MB"}
     else Result = $mod.FmtNum(GB * 1000000,0) + " kB";
    return Result;
  };
  this.FmtDv = function (Ms) {
    var Result = "";
    if (Math.abs(Ms) >= 1000) {
      Result = $mod.FmtNum(Ms / 1000,2) + " km/s"}
     else Result = $mod.FmtNum(Ms,0) + " m/s";
    return Result;
  };
  this.FmtDist = function (Km) {
    var Result = "";
    if (Km >= 1.0e9) {
      Result = $mod.FmtNum(Km / 1.0e9,2) + " billion km"}
     else if (Km >= 1.0e6) {
      Result = $mod.FmtNum(Km / 1.0e6,1) + " million km"}
     else Result = $mod.FmtNum(Km,0) + " km";
    return Result;
  };
  this.Plural = function (N, One, Many) {
    var Result = "";
    if (N === 1) {
      Result = pas.SysUtils.IntToStr(N) + " " + One}
     else Result = pas.SysUtils.IntToStr(N) + " " + Many;
    return Result;
  };
  this.ParseFloat = function (S) {
    var Result = 0.0;
    var I = 0;
    var Scale = 0.0;
    var Seen = false;
    var Frac = false;
    var Neg = false;
    Result = 0;
    Scale = 1;
    Seen = false;
    Frac = false;
    Neg = false;
    for (var $l = 1, $end = S.length; $l <= $end; $l++) {
      I = $l;
      if ((S.charAt(I - 1) >= "0") && (S.charAt(I - 1) <= "9")) {
        Seen = true;
        if (Frac) {
          Scale = Scale / 10;
          Result = Result + ((S.charCodeAt(I - 1) - 48) * Scale);
        } else Result = (Result * 10) + (S.charCodeAt(I - 1) - 48);
      } else if ((S.charAt(I - 1) === ".") && !Frac) {
        Frac = true}
       else if ((S.charAt(I - 1) === "-") && !Seen) {
        Neg = true}
       else if (Seen) break;
    };
    if (Neg) Result = -Result;
    return Result;
  };
  this.DayNumber = function (IsoDate) {
    var Result = 0;
    var Y = 0;
    var M = 0;
    var D = 0;
    var A = 0;
    var Yy = 0;
    var Mm = 0;
    Result = 0;
    if (IsoDate.length < 10) return Result;
    Y = pas.SysUtils.StrToIntDef(pas.System.Copy(IsoDate,1,4),0);
    M = pas.SysUtils.StrToIntDef(pas.System.Copy(IsoDate,6,2),0);
    D = pas.SysUtils.StrToIntDef(pas.System.Copy(IsoDate,9,2),0);
    if ((Y < 1900) || (M < 1) || (M > 12) || (D < 1) || (D > 31)) return Result;
    A = rtl.trunc((14 - M) / 12);
    Yy = (Y + 4800) - A;
    Mm = (M + (12 * A)) - 3;
    Result = (((D + rtl.trunc(((153 * Mm) + 2) / 5) + (365 * Yy) + rtl.trunc(Yy / 4)) - rtl.trunc(Yy / 100)) + rtl.trunc(Yy / 400)) - 32045 - 2451545;
    return Result;
  };
  var Mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  this.NiceDate = function (IsoDate) {
    var Result = "";
    var M = 0;
    var D = 0;
    Result = IsoDate;
    if (IsoDate.length < 10) return Result;
    M = pas.SysUtils.StrToIntDef(pas.System.Copy(IsoDate,6,2),0);
    D = pas.SysUtils.StrToIntDef(pas.System.Copy(IsoDate,9,2),0);
    if ((M < 1) || (M > 12) || (D < 1)) return Result;
    Result = pas.SysUtils.IntToStr(D) + " " + Mon[M - 1] + " " + pas.System.Copy(IsoDate,1,4);
    return Result;
  };
},["SysUtils","TsTypes"]);
rtl.module("TsScenarios",["System","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.Scenarios = [];
  this.EarthEvents = [];
  this.EarthEventsSource = "";
  this.SpaceWeather = [];
  this.SpaceWeatherSource = "";
  this.ApophisMissKm = 0.0;
  this.ApophisVelKmS = 0.0;
  this.ApophisDays = 0.0;
  this.ApophisDate = "";
  this.FindScenario = function (AId) {
    var Result = 0;
    var I = 0;
    Result = -1;
    for (var $l = 0, $end = rtl.length($mod.Scenarios) - 1; $l <= $end; $l++) {
      I = $l;
      if ($mod.Scenarios[I].Id === AId) {
        Result = I;
        return Result;
      };
    };
    return Result;
  };
  this.PrimaryMeasure = function (S) {
    var Result = 0;
    var M = 0;
    Result = 0;
    for (M = 0; M <= 8; M++) if (S.Weight[M] > S.Weight[Result]) Result = M;
    return Result;
  };
  this.EventVisible = function (O, Lat, Lon) {
    var Result = false;
    var Ang = 0.0;
    var DLon = 0.0;
    if (O.IsGeo) {
      DLon = ((Lon - O.GeoLon) * Math.PI) / 180;
      Ang = (Math.acos(pas.TsTypes.Clamp(Math.cos((Lat * Math.PI) / 180) * Math.cos(DLon),-1,1)) * 180) / Math.PI;
      Result = Ang <= 62;
    } else if (O.IncDeg >= 90) {
      Result = Math.abs(Lat) <= 86}
     else Result = Math.abs(Lat) <= (O.IncDeg + 4);
    return Result;
  };
  this.CategorySuit = function (Cat, M) {
    var Result = 0.0;
    Result = 0;
    if (Cat === "wildfires") {
      var $tmp = M;
      if ($tmp === 2) {
        Result = 1.0}
       else if ($tmp === 0) {
        Result = 0.5}
       else if ($tmp === 1) {
        Result = 0.5}
       else if ($tmp === 3) {
        Result = 0.3}
       else if ($tmp === 6) Result = 0.2;
    } else if (Cat === "severeStorms") {
      var $tmp1 = M;
      if ($tmp1 === 6) {
        Result = 1.0}
       else if ($tmp1 === 0) {
        Result = 0.6}
       else if ($tmp1 === 2) {
        Result = 0.4}
       else if ($tmp1 === 3) Result = 0.4;
    } else if (Cat === "volcanoes") {
      var $tmp2 = M;
      if ($tmp2 === 2) {
        Result = 1.0}
       else if ($tmp2 === 1) {
        Result = 0.6}
       else if ($tmp2 === 3) {
        Result = 0.6}
       else if ($tmp2 === 0) {
        Result = 0.5}
       else if ($tmp2 === 6) Result = 0.4;
    } else if (Cat === "floods") {
      var $tmp3 = M;
      if ($tmp3 === 3) {
        Result = 1.0}
       else if ($tmp3 === 0) {
        Result = 0.6}
       else if ($tmp3 === 1) {
        Result = 0.4}
       else if ($tmp3 === 2) Result = 0.2;
    } else if (Cat === "seaLakeIce") {
      var $tmp4 = M;
      if ($tmp4 === 3) {
        Result = 1.0}
       else if ($tmp4 === 0) {
        Result = 0.6}
       else if ($tmp4 === 2) {
        Result = 0.5}
       else if ($tmp4 === 6) Result = 0.2;
    } else if (Cat === "dustHaze") {
      var $tmp5 = M;
      if ($tmp5 === 0) {
        Result = 0.8}
       else if ($tmp5 === 6) {
        Result = 0.8}
       else if ($tmp5 === 1) Result = 0.5;
    } else if (Cat === "drought") {
      var $tmp6 = M;
      if ($tmp6 === 1) {
        Result = 0.9}
       else if ($tmp6 === 2) {
        Result = 0.8}
       else if ($tmp6 === 0) Result = 0.4;
    } else if ((Cat === "landslides") || (Cat === "earthquakes")) {
      var $tmp7 = M;
      if ($tmp7 === 3) {
        Result = 0.9}
       else if ($tmp7 === 0) Result = 0.8;
    } else {
      var $tmp8 = M;
      if ($tmp8 === 0) {
        Result = 0.5}
       else if ($tmp8 === 1) Result = 0.3;
    };
    return Result;
  };
  this.CategoryImportance = function (Cat) {
    var Result = 0.0;
    if (Cat === "severeStorms") {
      Result = 8}
     else if (Cat === "volcanoes") {
      Result = 6}
     else if (Cat === "floods") {
      Result = 3}
     else if (Cat === "drought") {
      Result = 3}
     else if (Cat === "landslides") {
      Result = 3}
     else if (Cat === "earthquakes") {
      Result = 3}
     else if (Cat === "seaLakeIce") {
      Result = 2}
     else if (Cat === "dustHaze") {
      Result = 2}
     else Result = 1;
    return Result;
  };
  this.CategoryLabel = function (Cat) {
    var Result = "";
    if (Cat === "wildfires") {
      Result = "Wildfires"}
     else if (Cat === "severeStorms") {
      Result = "Severe storms"}
     else if (Cat === "volcanoes") {
      Result = "Volcanoes"}
     else if (Cat === "floods") {
      Result = "Floods"}
     else if (Cat === "seaLakeIce") {
      Result = "Sea and lake ice"}
     else if (Cat === "dustHaze") {
      Result = "Dust and haze"}
     else if (Cat === "drought") {
      Result = "Drought"}
     else if (Cat === "landslides") {
      Result = "Landslides"}
     else if (Cat === "snow") {
      Result = "Snow"}
     else if (Cat === "tempExtremes") {
      Result = "Temperature extremes"}
     else if (Cat === "earthquakes") {
      Result = "Earthquakes"}
     else if (Cat === "waterColor") {
      Result = "Water colour"}
     else if (Cat === "manmade") {
      Result = "Human-made events"}
     else Result = Cat;
    return Result;
  };
  this.ApplyEarthEvents = function (Ev, ASource) {
    var SI = 0;
    var OI = 0;
    var I = 0;
    var M = 0;
    var Tot = rtl.arraySetLength(null,0.0,9);
    var Seen = rtl.arraySetLength(null,0.0,9);
    var W = 0.0;
    var MaxW = 0.0;
    var SumW = 0.0;
    var Imp = 0.0;
    var Vis = false;
    SI = $mod.FindScenario("earth");
    if ((SI < 0) || (rtl.length(Ev) < 10)) return;
    $mod.EarthEvents = rtl.arrayRef(Ev);
    $mod.EarthEventsSource = ASource;
    for (M = 0; M <= 8; M++) Tot[M] = 0;
    for (var $l = 0, $end = rtl.length(Ev) - 1; $l <= $end; $l++) {
      I = $l;
      Imp = $mod.CategoryImportance(Ev[I].Category);
      for (M = 0; M <= 8; M++) Tot[M] = Tot[M] + (Imp * $mod.CategorySuit(Ev[I].Category,M));
    };
    MaxW = 0;
    for (M = 0; M <= 8; M++) if (Tot[M] > MaxW) MaxW = Tot[M];
    if (MaxW <= 0) return;
    SumW = 0;
    for (M = 0; M <= 8; M++) {
      W = Math.round((100 * Tot[M]) / MaxW) / 100;
      $mod.Scenarios[SI].Weight[M] = W;
      SumW = SumW + W;
    };
    $mod.Scenarios[SI].FullScience = 0.45 * SumW;
    for (var $l1 = 0, $end1 = rtl.length($mod.Scenarios[SI].Orbits) - 1; $l1 <= $end1; $l1++) {
      OI = $l1;
      for (M = 0; M <= 8; M++) Seen[M] = 0;
      $mod.Scenarios[SI].Orbits[OI].EventsSeen = 0;
      $mod.Scenarios[SI].Orbits[OI].EventsTotal = rtl.length(Ev);
      for (var $l2 = 0, $end2 = rtl.length(Ev) - 1; $l2 <= $end2; $l2++) {
        I = $l2;
        Vis = $mod.EventVisible($mod.Scenarios[SI].Orbits[OI],Ev[I].Lat,Ev[I].Lon);
        if (Vis) {
          $mod.Scenarios[SI].Orbits[OI].EventsSeen += 1;
          Imp = $mod.CategoryImportance(Ev[I].Category);
          for (M = 0; M <= 8; M++) Seen[M] = Seen[M] + (Imp * $mod.CategorySuit(Ev[I].Category,M));
        };
      };
      for (M = 0; M <= 8; M++) if (Tot[M] > 0) {
        $mod.Scenarios[SI].Orbits[OI].Factor[M] = ($mod.Scenarios[SI].Orbits[OI].Base[M] * Seen[M]) / Tot[M]}
       else $mod.Scenarios[SI].Orbits[OI].Factor[M] = $mod.Scenarios[SI].Orbits[OI].Base[M];
      $mod.Scenarios[SI].Orbits[OI].Coverage = 1.0;
    };
  };
  this.ApplySpaceWeather = function (Sw, ASource) {
    if (rtl.length(Sw) === 0) return;
    $mod.SpaceWeather = rtl.arrayRef(Sw);
    $mod.SpaceWeatherSource = ASource;
  };
  this.WeatherStrength = function (Kind, ClassType) {
    var Result = 0.0;
    var N = 0.0;
    Result = 0.3;
    if (Kind === "FLR") {
      N = pas.TsFmt.ParseFloat(pas.System.Copy(ClassType,2,8));
      if ((ClassType.length > 0) && (ClassType.charAt(0) === "X")) {
        Result = 0.5 + pas.TsTypes.MinD(0.5,N / 20)}
       else Result = 0.2 + pas.TsTypes.MinD(0.2,N * 0.02);
    } else if (Kind === "GST") {
      Result = pas.TsTypes.Clamp(pas.TsFmt.ParseFloat(ClassType) / 9,0.1,1)}
     else if (Kind === "SEP") Result = 0.7;
    return Result;
  };
  this.WeatherLabel = function (W) {
    var Result = "";
    if (W.Kind === "FLR") {
      Result = "class " + W.ClassType + " solar flare"}
     else if (W.Kind === "GST") {
      Result = "geomagnetic storm (" + W.ClassType + ")"}
     else Result = "solar energetic particle storm";
    Result = Result + " on " + pas.TsFmt.NiceDate(W.Date);
    return Result;
  };
  this.ApplyApophis = function (DaysToFlyby, MissKm, VelKmS, ADate) {
    var SI = 0;
    SI = $mod.FindScenario("apophis");
    if (SI < 0) return;
    $mod.ApophisDays = DaysToFlyby;
    $mod.ApophisMissKm = MissKm;
    $mod.ApophisVelKmS = VelKmS;
    $mod.ApophisDate = ADate;
    $mod.Scenarios[SI].DeadlineYears = pas.TsTypes.MaxD(2.0,(DaysToFlyby / 365.25) - 0.08);
  };
  $mod.$implcode = function () {
    $impl.AddWeather = function (AKind, ADate, AClass) {
      var N = 0;
      N = rtl.length($mod.SpaceWeather);
      $mod.SpaceWeather = rtl.arraySetLength($mod.SpaceWeather,pas.TsTypes.TSpaceWeather,N + 1);
      $mod.SpaceWeather[N].Kind = AKind;
      $mod.SpaceWeather[N].Date = ADate;
      $mod.SpaceWeather[N].ClassType = AClass;
      $mod.SpaceWeather[N].Strength = $mod.WeatherStrength(AKind,AClass);
    };
    $impl.BuildFallbackWeather = function () {
      $impl.AddWeather("GST","2022-02-04","Kp 5");
      $impl.AddWeather("SEP","2017-09-10","SEP");
      $impl.AddWeather("FLR","2017-09-10","X8.2");
      $impl.AddWeather("FLR","2003-10-28","X17");
      $impl.AddWeather("SEP","2003-10-28","SEP");
      $impl.AddWeather("GST","2024-05-10","Kp 9");
      $impl.AddWeather("FLR","2024-05-14","X8.7");
      $impl.AddWeather("FLR","2024-10-03","X9.0");
      $mod.SpaceWeatherSource = "historic events (NASA)";
    };
    $impl.NewOrbit = function (AId, AName, ABlurb, AWhy) {
      var Result = pas.TsTypes.TOrbit.$new();
      var M = 0;
      Result.Id = AId;
      Result.Name = AName;
      Result.Blurb = ABlurb;
      Result.Why = AWhy;
      Result.AltKm = 0;
      Result.ApoKm = 0;
      Result.IncDeg = 0;
      Result.PeriodHr = 2;
      Result.EclipseFrac = 0;
      Result.MaxEclipseHr = 0;
      Result.Coverage = 1;
      for (M = 0; M <= 8; M++) {
        Result.Factor[M] = 1;
        Result.Base[M] = 1;
      };
      Result.EventsSeen = 0;
      Result.EventsTotal = 0;
      Result.TauFactor = 1;
      Result.DataFactor = 1;
      Result.CommFactor = 1;
      Result.RangeKm = 0;
      Result.DvInsert = 0;
      Result.DvPerYear = 0;
      Result.LvMode = 3;
      Result.C3 = 0;
      Result.ExtraYears = 0;
      Result.InsertRisk = 0;
      Result.RadLevel = 1;
      Result.RadLifeYears = 0;
      Result.DragLifeYears = 0;
      Result.NeedsDeorbit = false;
      Result.IsGeo = false;
      Result.GeoLon = 0;
      return Result;
    };
    $impl.SetFactors = function (O, V) {
      var M = 0;
      for (M = 0; M <= 8; M++) {
        O.Factor[M] = V[M];
        O.Base[M] = V[M];
      };
    };
    $impl.AddOrbit = function (S, O) {
      var N = 0;
      N = rtl.length(S.Orbits);
      S.Orbits = rtl.arraySetLength(S.Orbits,pas.TsTypes.TOrbit,N + 1);
      S.Orbits[N].$assign(O);
      if (S.Orbits[N].ApoKm === 0) S.Orbits[N].ApoKm = S.Orbits[N].AltKm;
    };
    $impl.AddTransfer = function (S, AId, AName, ABlurb, AC3, ACruise, ADvFactor, AHot) {
      var N = 0;
      N = rtl.length(S.Transfers);
      S.Transfers = rtl.arraySetLength(S.Transfers,pas.TsTypes.TTransfer,N + 1);
      S.Transfers[N].Id = AId;
      S.Transfers[N].Name = AName;
      S.Transfers[N].Blurb = ABlurb;
      S.Transfers[N].C3 = AC3;
      S.Transfers[N].CruiseYears = ACruise;
      S.Transfers[N].DvFactor = ADvFactor;
      S.Transfers[N].HotFlyby = AHot;
    };
    $impl.AddAnalog = function (S, AName, AAgency, AYear, ABlurb, AUrl, AMass, ACost, AInstr) {
      var N = 0;
      N = rtl.length(S.Analogs);
      S.Analogs = rtl.arraySetLength(S.Analogs,pas.TsTypes.TAnalog,N + 1);
      S.Analogs[N].Name = AName;
      S.Analogs[N].Agency = AAgency;
      S.Analogs[N].Year = AYear;
      S.Analogs[N].Blurb = ABlurb;
      S.Analogs[N].Url = AUrl;
      S.Analogs[N].MassKg = AMass;
      S.Analogs[N].CostM = ACost;
      S.Analogs[N].Instruments = AInstr;
    };
    $impl.NewScenario = function (AId, AName, ATagline, ABody, ALevel) {
      var Result = pas.TsTypes.TScenario.$new();
      var M = 0;
      Result.Id = AId;
      Result.Name = AName;
      Result.Tagline = ATagline;
      Result.Body = ABody;
      Result.Brief = "";
      Result.Objective = "";
      Result.Level = ALevel;
      Result.CostCapM = 100;
      Result.DeadlineYears = 4;
      Result.WindowYears = 0;
      Result.WindowPeriod = 0;
      Result.ArriveBy = false;
      Result.LateFactor = 1;
      Result.MinLife = 1;
      Result.MaxLife = 5;
      Result.DefaultLife = 2;
      Result.SunAU = 1;
      Result.EarthMinAU = 0;
      Result.EarthMaxAU = 0;
      Result.SynodicDays = 0;
      Result.NearEarth = false;
      Result.DataScale = 1;
      Result.HeaterW = 0;
      Result.ColdWorld = false;
      Result.AllowRTG = false;
      Result.AllowSEP = false;
      Result.SepDvFactor = 1;
      Result.SepExtraYears = 0;
      for (M = 0; M <= 8; M++) Result.Weight[M] = 0;
      Result.FullScience = 2;
      Result.ThresholdPct = 40;
      Result.TauYears = 1;
      Result.Orbits = rtl.arraySetLength(Result.Orbits,pas.TsTypes.TOrbit,0);
      Result.Transfers = rtl.arraySetLength(Result.Transfers,pas.TsTypes.TTransfer,0);
      Result.Instruments = rtl.arraySetLength(Result.Instruments,"",0);
      Result.Analogs = rtl.arraySetLength(Result.Analogs,pas.TsTypes.TAnalog,0);
      Result.Facts = rtl.arraySetLength(Result.Facts,"",0);
      Result.UsesEonet = false;
      Result.UsesApophis = false;
      return Result;
    };
    $impl.AddScenario = function (S) {
      var N = 0;
      N = rtl.length($mod.Scenarios);
      $mod.Scenarios = rtl.arraySetLength($mod.Scenarios,pas.TsTypes.TScenario,N + 1);
      $mod.Scenarios[N].$assign(S);
    };
    $impl.Offer = function (S, Ids) {
      var I = 0;
      for (var $l = 0, $end = rtl.length(Ids) - 1; $l <= $end; $l++) {
        I = $l;
        pas.TsTypes.AddStr({p: S, get: function () {
            return this.p.Instruments;
          }, set: function (v) {
            this.p.Instruments = v;
          }},Ids[I]);
      };
    };
    $impl.BuildEarth = function () {
      var S = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      S.$assign($impl.NewScenario("earth","Disaster Watch","Keep watch over a restless planet","Earth",1));
      S.Brief = "Right now, satellites are tracking hundreds of wildfires, floods, storms and ice " + "events around the world. NASA's Earth Observatory Natural Event Tracker (EONET) lists " + "them as they happen, and emergency teams need eyes on every one.";
      S.Objective = "Build a small Earth-observation satellite that can see as many of today's real " + "natural events as possible, with the right instruments, and get the data home.";
      S.CostCapM = 120;
      S.DeadlineYears = 3.5;
      S.MinLife = 1;
      S.MaxLife = 7;
      S.DefaultLife = 3;
      S.SunAU = 1;
      S.NearEarth = true;
      S.Weight = pas.TsCatalog.MV(0.7,0.5,1.0,0.85,0.2,0,0.9,0.1,0);
      S.FullScience = 1.9;
      S.ThresholdPct = 40;
      S.TauYears = 1.5;
      S.UsesEonet = true;
      O.$assign($impl.NewOrbit("iss","Mid-inclination low orbit","420 km high, tilted 51.6 degrees, like the Space Station.","Flies over everywhere between 52 N and 52 S, where most people live. It never sees the far north or south, " + "and thin air this low slowly drags the satellite down."));
      O.AltKm = 420;
      O.IncDeg = 51.6;
      O.PeriodHr = 1.55;
      O.EclipseFrac = 0.38;
      O.MaxEclipseHr = 0.6;
      O.Coverage = 0.8;
      O.CommFactor = 0.9;
      O.RangeKm = 2000;
      O.LvMode = 0;
      O.DvPerYear = 30;
      O.RadLevel = 0;
      O.DragLifeYears = 1.5;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("tropic","Tropical low orbit","550 km high, tilted only 30 degrees.","Stays over the tropics and comes back to the same storm again and again. Blind to everything beyond 34 degrees latitude."));
      O.AltKm = 550;
      O.IncDeg = 30;
      O.PeriodHr = 1.6;
      O.EclipseFrac = 0.36;
      O.MaxEclipseHr = 0.6;
      O.Coverage = 0.5;
      O.CommFactor = 0.7;
      O.RangeKm = 2200;
      $impl.SetFactors(O,pas.TsCatalog.MV(1,1,1,1,1,1,1.15,1,1));
      O.LvMode = 0;
      O.DvPerYear = 8;
      O.RadLevel = 0;
      O.DragLifeYears = 6;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("sso","Sun-synchronous polar orbit","700 km high, passing near both poles.","Sees the whole planet, always in the same lighting, and polar ground stations hear it on every lap. " + "So high that it would stay up for centuries, so it must carry fuel to bring itself down."));
      O.AltKm = 700;
      O.IncDeg = 98;
      O.PeriodHr = 1.65;
      O.EclipseFrac = 0.30;
      O.MaxEclipseHr = 0.6;
      O.Coverage = 1.0;
      O.CommFactor = 1.25;
      O.RangeKm = 2500;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.95,1,0.95,0.95,0.95,1,0.95,1,1));
      O.LvMode = 1;
      O.DvPerYear = 3;
      O.RadLevel = 0;
      O.NeedsDeorbit = true;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("geo_am","Geostationary: Americas","35,786 km up, parked over 75 W.","Stares at the Americas without ever blinking, perfect for following a storm minute by minute. " + "But it is 85 times farther away than a low orbit, so detail is poor, radar is impossible and getting there takes a big engine burn."));
      O.AltKm = 35786;
      O.IncDeg = 0;
      O.PeriodHr = 24;
      O.EclipseFrac = 0.02;
      O.MaxEclipseHr = 1.2;
      O.Coverage = 0.38;
      O.CommFactor = 20;
      O.RangeKm = 38000;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.4,0.35,0.85,0.03,0.1,1,1.35,1,1));
      O.LvMode = 2;
      O.DvInsert = 1500;
      O.DvPerYear = 50;
      O.RadLevel = 1;
      O.IsGeo = true;
      O.GeoLon = -75;
      $impl.AddOrbit(S,O);
      O.Id = "geo_af";
      O.Name = "Geostationary: Africa and Europe";
      O.Blurb = "35,786 km up, parked over 20 E.";
      O.Why = "The same unblinking stare, centred on Africa and Europe. Great for fires and storms there, blind to the rest of the world.";
      O.GeoLon = 20;
      $impl.AddOrbit(S,O);
      O.Id = "geo_as";
      O.Name = "Geostationary: Asia and Pacific";
      O.Blurb = "35,786 km up, parked over 140 E.";
      O.Why = "Centred on East Asia, Australia and the western Pacific, where typhoons are born.";
      O.GeoLon = 140;
      $impl.AddOrbit(S,O);
      $impl.AddTransfer(S,"direct","Direct launch","The rocket drops the satellite straight into its orbit.",0,0,1,false);
      $impl.Offer(S,["cam_ctx","cam_hires","spec_vnir","tir","sar","radiometer","uvs"]);
      $impl.AddAnalog(S,"Landsat 9","NASA / USGS","2021","Sun-synchronous orbit at 705 km. Two instruments: a multispectral imager and a thermal imager.","https://science.nasa.gov/mission/landsat-9/",2711,750,2);
      $impl.AddAnalog(S,"TROPICS","NASA","2023","Four 5 kg CubeSats in a 30 degree orbit, each with one microwave radiometer, revisiting storms about hourly.","https://science.nasa.gov/mission/tropics/",21,30,1);
      $impl.AddAnalog(S,"NISAR","NASA / ISRO","2025","A joint US-India radar satellite that maps almost all land and ice every 12 days, day or night, through cloud.","https://science.nasa.gov/mission/nisar/",2400,1500,2);
      $impl.AddAnalog(S,"CYGNSS","NASA","2016","Eight microsatellites in a 35 degree orbit measuring winds inside hurricanes.","https://science.nasa.gov/mission/cygnss/",232,157,1);
      $impl.AddAnalog(S,"Terra","NASA with Japan and Canada","1999","A bus-sized observatory with five instruments, including ASTER from Japan and MOPITT from Canada.","https://terra.nasa.gov/",5190,1300,5);
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"The TROPICS CubeSats weigh about 5 kg each, yet together they revisit a hurricane roughly every hour.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"The first two TROPICS satellites were lost when their rocket failed in 2022. The mission survived because it had built spares.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"NISAR, built by NASA and ISRO, can measure the ground moving by less than a centimetre from 747 km up.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"A geostationary satellite sits 35,786 km up, almost a tenth of the way to the Moon.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"A sun-synchronous satellite crosses the equator at the same local time on every orbit, so shadows always fall the same way.");
      $impl.AddScenario(S);
    };
    $impl.BuildMoon = function () {
      var S = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      S.$assign($impl.NewScenario("moon","Ice Prospector","Find the water at the Moon's south pole","Moon",1));
      S.Brief = "Craters near the Moon's south pole have not seen sunlight for two billion years. " + "Earlier missions found signs of hydrogen there, probably water ice. Future astronauts could drink it, " + "breathe it and turn it into rocket fuel, if we know exactly where it is.";
      S.Objective = "Map water ice and other volatiles at the lunar poles from orbit for at least one year.";
      S.CostCapM = 150;
      S.DeadlineYears = 4;
      S.MinLife = 1;
      S.MaxLife = 5;
      S.DefaultLife = 2;
      S.SunAU = 1;
      S.EarthMinAU = 0.00257;
      S.EarthMaxAU = 0.00257;
      S.DataScale = 0.5;
      S.HeaterW = 10;
      S.AllowSEP = true;
      S.SepDvFactor = 2.2;
      S.SepExtraYears = 1.0;
      S.Weight = pas.TsCatalog.MV(0.45,0.8,0.6,0.6,0.5,1.0,0.05,0.1,0);
      S.FullScience = 1.9;
      S.ThresholdPct = 40;
      S.TauYears = 0.7;
      O.$assign($impl.NewOrbit("polar100","Low polar orbit","A 100 km circle passing over both poles every two hours.","The classic mapping orbit, used by Lunar Reconnaissance Orbiter. Every instrument works well here, " + "but lumps in the Moon's gravity keep pulling the orbit out of shape, so it costs fuel every year."));
      O.AltKm = 100;
      O.IncDeg = 90;
      O.PeriodHr = 1.96;
      O.EclipseFrac = 0.38;
      O.MaxEclipseHr = 0.8;
      O.CommFactor = 0.6;
      O.DvInsert = 850;
      O.DvPerYear = 60;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("frozen","Elliptical frozen orbit","30 km over the south pole, 220 km over the north.","A special shape that the Moon's lumpy gravity leaves almost alone, so it needs hardly any fuel. " + "It skims the south pole for superb detail there, at the price of a poorer view of the north."));
      O.AltKm = 30;
      O.ApoKm = 220;
      O.IncDeg = 90;
      O.PeriodHr = 2.0;
      O.EclipseFrac = 0.33;
      O.MaxEclipseHr = 0.8;
      O.Coverage = 0.85;
      O.CommFactor = 0.65;
      O.DvInsert = 880;
      O.DvPerYear = 8;
      $impl.SetFactors(O,pas.TsCatalog.MV(1.25,1.1,1.1,1.2,1.2,1.3,1,1,1));
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("nrho","Near-rectilinear halo orbit","A week-long loop from 3,000 km to 70,000 km above the Moon.","The orbit of the planned Gateway station, pioneered by the CAPSTONE CubeSat. Almost free to reach and to keep, " + "always in sunlight and always in view of Earth. But it is far too high for instruments that need to be close."));
      O.AltKm = 3000;
      O.ApoKm = 70000;
      O.IncDeg = 90;
      O.PeriodHr = 156;
      O.EclipseFrac = 0.0;
      O.MaxEclipseHr = 1.5;
      O.Coverage = 0.9;
      O.CommFactor = 1.5;
      O.DvInsert = 450;
      O.DvPerYear = 10;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.12,0.2,0.2,0.05,0.05,0.02,1,1,1));
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("equator","Low equatorial orbit","A 100 km circle around the Moon's equator.","Easy to reach, but an orbit can only fly over latitudes up to its tilt. This one never goes near the poles, where the ice is."));
      O.AltKm = 100;
      O.IncDeg = 0;
      O.PeriodHr = 1.96;
      O.EclipseFrac = 0.40;
      O.MaxEclipseHr = 0.8;
      O.Coverage = 0.08;
      O.CommFactor = 0.6;
      O.DvInsert = 820;
      O.DvPerYear = 60;
      $impl.AddOrbit(S,O);
      $impl.AddTransfer(S,"direct","Direct transfer (5 days)","Straight there, then a hard braking burn to be captured.",-2,0.014,1,false);
      $impl.AddTransfer(S,"blt","Ballistic lunar transfer (4 months)","A long loop 1.5 million km out, where the Sun's gravity does a quarter of the braking for free. Used by CAPSTONE and Danuri.",-0.6,0.33,0.75,false);
      $impl.Offer(S,["neutron","spec_vnir","tir","sar","lidar","cam_ctx","cam_hires","uvs","mag","dust","radio"]);
      $impl.AddAnalog(S,"Lunar Reconnaissance Orbiter","NASA","2009","Seven instruments in a low polar orbit. Still working after more than 15 years.","https://science.nasa.gov/mission/lro/",1916,504,7);
      $impl.AddAnalog(S,"Lunar Prospector","NASA","1998","A simple spinning probe whose neutron spectrometer found the first signs of polar hydrogen.","https://science.nasa.gov/mission/lunar-prospector/",296,63,5);
      $impl.AddAnalog(S,"Lunar Trailblazer","NASA","2025","A 200 kg SmallSat with a spectrometer and a thermal mapper. It rode along with another launch and fell silent a day later.","https://science.nasa.gov/mission/lunar-trailblazer/",200,94,2);
      $impl.AddAnalog(S,"CAPSTONE","NASA","2022","A 25 kg CubeSat launched on an Electron. First spacecraft in a near-rectilinear halo orbit.","https://www.nasa.gov/mission/capstone/",25,33,1);
      $impl.AddAnalog(S,"Chandrayaan-1","ISRO with NASA instruments","2008","India's first Moon mission. NASA's M3 spectrometer on board found water molecules on the surface.","https://science.nasa.gov/mission/chandrayaan-1/",1380,80,11);
      $impl.AddAnalog(S,"Danuri","KARI (Korea) with NASA ShadowCam","2022","South Korea's first lunar orbiter, sent on a fuel-saving ballistic transfer.","https://science.nasa.gov/mission/danuri/",678,180,6);
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Lunar Prospector found signs of polar hydrogen in 1998 with a neutron spectrometer weighing about 4 kg.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"CAPSTONE took a four-month looping route to the Moon to save fuel, travelling 1.5 million km from Earth on the way.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"India's Chandrayaan-1 carried NASA's M3 spectrometer, which found water molecules across the lunar surface.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Lunar Trailblazer, a low-cost SmallSat, fell silent a day after its 2025 launch. Lean missions accept more risk.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"ESA's SMART-1 reached the Moon using an ion engine. The trip took 13 months instead of 5 days.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"A radio signal takes about 1.3 seconds to travel between Earth and the Moon.");
      $impl.AddScenario(S);
    };
    $impl.BuildMars = function () {
      var S = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      S.$assign($impl.NewScenario("mars","Follow the Water","Track the weather and water of the Red Planet","Mars",2));
      S.Brief = "Mars once had rivers and lakes. Today its water is locked in ice, hidden underground or lost to space. " + "Before people go, we need to know where the water went and what weather they will face. " + "The planets only line up for the trip once every 26 months.";
      S.Objective = "Study the Martian atmosphere, water and climate from orbit for a full Mars year (about two Earth years), " + "and relay data for missions on the surface if you can.";
      S.CostCapM = 650;
      S.DeadlineYears = 4.4;
      S.WindowYears = 2.1;
      S.WindowPeriod = 2.14;
      S.MinLife = 2;
      S.MaxLife = 8;
      S.DefaultLife = 2;
      S.SunAU = 1.6;
      S.EarthMinAU = 0.52;
      S.EarthMaxAU = 2.52;
      S.SynodicDays = 780;
      S.DataScale = 0.05;
      S.HeaterW = 20;
      S.AllowSEP = true;
      S.SepDvFactor = 1.6;
      S.SepExtraYears = 0.8;
      S.Weight = pas.TsCatalog.MV(0.7,0.7,0.5,0.6,0.3,0.3,1.0,0.45,0.5);
      S.FullScience = 2.3;
      S.ThresholdPct = 40;
      S.TauYears = 1.0;
      O.$assign($impl.NewOrbit("low_aero","Low orbit by aerobraking","A 300 km sun-synchronous orbit, reached by skimming the atmosphere for six months.","Brake into a long looping orbit, then dip into the top of the atmosphere on every pass and let drag do the rest. " + "It saves over a kilometre per second of fuel, but costs half a year and a little risk."));
      O.AltKm = 300;
      O.IncDeg = 93;
      O.PeriodHr = 1.87;
      O.EclipseFrac = 0.35;
      O.MaxEclipseHr = 0.7;
      O.CommFactor = 0.7;
      O.DvInsert = 1150;
      O.DvPerYear = 15;
      O.ExtraYears = 0.5;
      O.InsertRisk = 0.015;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("low_prop","Low orbit by engine alone","The same 300 km orbit, reached entirely with rocket burns.","No waiting and no skimming the atmosphere: science starts at once. But the fuel bill more than doubles."));
      O.AltKm = 300;
      O.IncDeg = 93;
      O.PeriodHr = 1.87;
      O.EclipseFrac = 0.35;
      O.MaxEclipseHr = 0.7;
      O.CommFactor = 0.7;
      O.DvInsert = 2450;
      O.DvPerYear = 15;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("ellip","Elliptical dipping orbit","From 150 km out to 6,200 km, like MAVEN.","Dives through the upper atmosphere, then swings far out to watch the whole planet. Ideal for studying how Mars loses its air. " + "Cameras and radar suffer, because the spacecraft is seldom low for long."));
      O.AltKm = 150;
      O.ApoKm = 6200;
      O.IncDeg = 75;
      O.PeriodHr = 4.5;
      O.EclipseFrac = 0.15;
      O.MaxEclipseHr = 1.0;
      O.Coverage = 0.9;
      O.CommFactor = 0.85;
      O.DvInsert = 1250;
      O.DvPerYear = 10;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.5,0.6,0.6,0.5,0.3,1.4,1.15,1.4,0.9));
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("areo","Areostationary orbit","17,032 km up, hovering over one spot on the equator.","The Martian version of a geostationary orbit. It watches one side of the planet's weather all day and is a perfect relay station, " + "but from this height the surface is a blur."));
      O.AltKm = 17032;
      O.IncDeg = 0;
      O.PeriodHr = 24.6;
      O.EclipseFrac = 0.02;
      O.MaxEclipseHr = 1.3;
      O.Coverage = 0.45;
      O.CommFactor = 0.95;
      O.DvInsert = 1900;
      O.DvPerYear = 5;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.15,0.2,0.4,0.02,0.05,0.1,1.2,0.6,1.6));
      $impl.AddOrbit(S,O);
      $impl.AddTransfer(S,"hohmann","Seven-month transfer","The standard fuel-saving path used by nearly every Mars mission.",12,0.58,1,false);
      $impl.Offer(S,["radiometer","cam_ctx","cam_hires","spec_vnir","tir","sar","massspec","mag","plasma","uvs","lidar","relay","radio"]);
      $impl.AddAnalog(S,"Mars Reconnaissance Orbiter","NASA","2005","Six instruments and a 3 m dish. It aerobraked for six months and has returned more data than all other planetary missions combined.","https://science.nasa.gov/mission/mars-reconnaissance-orbiter/",2180,720,6);
      $impl.AddAnalog(S,"MAVEN","NASA","2013","Eight instruments in an elliptical orbit that dips into the upper atmosphere to study how Mars loses its air.","https://science.nasa.gov/mission/maven/",2454,671,8);
      $impl.AddAnalog(S,"Mars Odyssey","NASA","2001","Found vast amounts of buried ice and has relayed data for every NASA rover since.","https://science.nasa.gov/mission/odyssey/",725,297,3);
      $impl.AddAnalog(S,"Hope","UAE Space Agency / MBRSC","2020","Orbits very high so it can see a whole hemisphere of weather at once.","https://www.emiratesmarsmission.ae/",1350,200,3);
      $impl.AddAnalog(S,"Mangalyaan","ISRO","2013","India reached Mars orbit at the first attempt for about 74 million dollars.","https://www.isro.gov.in/MarsOrbiterMissionSpacecraft.html",1337,74,5);
      $impl.AddAnalog(S,"ESCAPADE","NASA","2025","Two SmallSats studying how the solar wind strips the Martian atmosphere.","https://science.nasa.gov/mission/escapade/",1070,80,3);
      $impl.AddAnalog(S,"MarCO","NASA","2018","Two briefcase-sized CubeSats that relayed the InSight landing live from Mars.","https://science.nasa.gov/mission/marco/",27,18.5,0);
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"MRO spent six months skimming the top of Mars's atmosphere to shrink its orbit, saving hundreds of kilograms of fuel.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Mars Climate Orbiter was lost in 1999 because one team worked in pounds and another in newtons.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Radio signals take between 3 and 22 minutes to cross from Mars to Earth, so nobody can fly a Mars orbiter by joystick.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Every 26 months Mars slips behind the Sun and its spacecraft go quiet for about two weeks.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Sunlight at Mars is less than half as strong as at Earth, so solar panels must be more than twice the size.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"MRO's 3 m dish and 100 W transmitter send about 0.5 to 6 megabits per second, depending on how far away Mars is.");
      $impl.AddScenario(S);
    };
    $impl.BuildApophis = function () {
      var S = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      S.$assign($impl.NewScenario("apophis","Race to Apophis","Meet an asteroid before it meets Earth","Apophis",2));
      S.Brief = "On 13 April 2029 the asteroid 99942 Apophis, a rock about 340 m wide, will skim past Earth closer than " + "our TV satellites. It will not hit us, but Earth's gravity will tug it, twist it and may even shake its surface. " + "Nothing this large comes this close more than once in thousands of years, and the date cannot move.";
      S.Objective = "Get a spacecraft to Apophis in time to watch what Earth's gravity does to it. " + "The real question is what you can build before the clock runs out.";
      S.CostCapM = 250;
      S.DeadlineYears = 2.33;
      S.ArriveBy = true;
      S.LateFactor = 0.6;
      S.MinLife = 0.5;
      S.MaxLife = 3;
      S.DefaultLife = 1;
      S.SunAU = 1.05;
      S.EarthMinAU = 0.02;
      S.EarthMaxAU = 0.55;
      S.SynodicDays = 560;
      S.DataScale = 0.05;
      S.HeaterW = 5;
      S.AllowSEP = true;
      S.SepDvFactor = 1.1;
      S.SepExtraYears = 0.2;
      S.Weight = pas.TsCatalog.MV(0.9,0.9,0.7,0.7,0.8,0.4,0,0.25,0);
      S.FullScience = 1.4;
      S.ThresholdPct = 30;
      S.TauYears = 0.35;
      S.UsesApophis = true;
      O.$assign($impl.NewOrbit("rdv","Rendezvous and stay","Match speed with the asteroid and fly alongside it for months.","You watch the whole flyby from close up and map every boulder before and after. It takes a real engine to slow down and stay."));
      O.AltKm = 2;
      O.IncDeg = 90;
      O.PeriodHr = 30;
      O.EclipseFrac = 0.05;
      O.MaxEclipseHr = 1.0;
      O.DvInsert = 950;
      O.DvPerYear = 30;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("flyby","Fast flyby","Race past once at several kilometres per second.","Almost no fuel and a smaller rocket, but all the science happens in a few frantic hours and you see only one side."));
      O.AltKm = 500;
      O.IncDeg = 0;
      O.PeriodHr = 2;
      O.EclipseFrac = 0;
      O.MaxEclipseHr = 0;
      O.Coverage = 0.45;
      O.TauFactor = 0.05;
      O.DataFactor = 0.05;
      O.DvInsert = 80;
      O.DvPerYear = 0;
      O.C3 = -3;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.9,0.8,0.8,0.3,0.3,0.6,1,0.6,1));
      $impl.AddOrbit(S,O);
      $impl.AddTransfer(S,"fast","Fast transfer (4 months)","Leave late and fly hard. Needs more launch energy, so a bigger rocket per kilogram.",25,0.35,1,false);
      $impl.AddTransfer(S,"slow","Low-energy transfer (19 months)","A gentle path that a small rocket can manage, with a quarter less braking. You must leave much earlier.",3,1.6,0.75,false);
      $impl.Offer(S,["cam_ctx","cam_hires","spec_vnir","tir","lidar","sar","dust","mag","radio"]);
      $impl.AddAnalog(S,"OSIRIS-APEX","NASA","2029 arrival","The OSIRIS-REx spacecraft, sent on to Apophis after delivering its Bennu sample. It arrives just after the flyby.","https://science.nasa.gov/mission/osiris-apex/",2110,200,5);
      $impl.AddAnalog(S,"Ramses","ESA with JAXA","planned 2028","A European mission planned to launch in 2028 and reach Apophis before the flyby.","https://www.esa.int/Space_Safety/Planetary_Defence/Introducing_Ramses_ESA_s_mission_to_asteroid_Apophis",1200,400,4);
      $impl.AddAnalog(S,"DART","NASA with ASI's LICIACube","2021","Crashed into the asteroid moon Dimorphos and changed its orbit, the first planetary-defence test.","https://science.nasa.gov/mission/dart/",610,325,1);
      $impl.AddAnalog(S,"NEAR Shoemaker","NASA","1996","The first spacecraft to orbit and then land on an asteroid, Eros.","https://science.nasa.gov/mission/near-shoemaker/",805,224,6);
      $impl.AddAnalog(S,"Hayabusa2","JAXA","2014","Used ion engines to reach asteroid Ryugu and bring samples back to Earth.","https://www.hayabusa2.jaxa.jp/en/",609,150,5);
      $impl.AddAnalog(S,"OSIRIS-REx","NASA with a Canadian laser altimeter","2016","Mapped asteroid Bennu in detail and returned a sample in 2023.","https://science.nasa.gov/mission/osiris-rex/",2110,1000,5);
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Apophis will pass about 32,000 km above Earth's surface, inside the ring of geostationary satellites.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"On the night of the flyby Apophis will be visible to the naked eye from Africa, Europe and western Asia.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"After delivering its Bennu sample, NASA's OSIRIS-REx was renamed OSIRIS-APEX and sent on to Apophis.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"DART proved in 2022 that a spacecraft can change an asteroid's path by crashing into it.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Japan's Hayabusa2 used ion engines to visit asteroid Ryugu and bring samples home.");
      $impl.AddScenario(S);
    };
    $impl.BuildEuropa = function () {
      var S = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      S.$assign($impl.NewScenario("europa","Ocean World","Is there an ocean we could live in?","Europa",3));
      S.Brief = "Under the cracked ice of Jupiter's moon Europa lies a salt-water ocean holding more water than all of " + "Earth's seas. It is one of the best places to look for life. But Jupiter is five times farther from the Sun than we are, " + "so sunlight is 27 times weaker, and its radiation belts can kill electronics in weeks.";
      S.Objective = "Measure the thickness of Europa's ice shell and the nature of its ocean, and survive long enough to send the answer home.";
      S.CostCapM = 2000;
      S.DeadlineYears = 9;
      S.MinLife = 0.25;
      S.MaxLife = 6;
      S.DefaultLife = 3.5;
      S.SunAU = 5.2;
      S.EarthMinAU = 4.2;
      S.EarthMaxAU = 6.2;
      S.SynodicDays = 399;
      S.DataScale = 0.01;
      S.HeaterW = 60;
      S.ColdWorld = true;
      S.AllowRTG = true;
      S.Weight = pas.TsCatalog.MV(0.8,0.8,0.6,1.0,0.6,0.7,0.15,0.9,0);
      S.FullScience = 3.0;
      S.ThresholdPct = 40;
      S.TauYears = 1.3;
      O.$assign($impl.NewOrbit("tour","Europa flyby tour","Orbit Jupiter and swoop past Europa about 45 times.","The Europa Clipper plan. Each pass maps a new strip, then the spacecraft retreats from the radiation to send its data home. " + "Slower than orbiting Europa, but the electronics live for years."));
      O.AltKm = 50;
      O.ApoKm = 2500000;
      O.IncDeg = 10;
      O.PeriodHr = 500;
      O.EclipseFrac = 0.03;
      O.MaxEclipseHr = 3;
      O.Coverage = 0.85;
      O.CommFactor = 0.9;
      O.DvInsert = 1500;
      O.DvPerYear = 40;
      O.RadLevel = 2;
      O.RadLifeYears = 4.5;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("orbiter","Europa orbiter","Circle Europa itself at 100 km.","The dream orbit: complete maps in weeks and the best gravity and radar data possible. " + "But it sits deep in the radiation belt all the time, and braking into it takes almost twice the fuel."));
      O.AltKm = 100;
      O.IncDeg = 90;
      O.PeriodHr = 2.1;
      O.EclipseFrac = 0.30;
      O.MaxEclipseHr = 0.8;
      O.Coverage = 1.0;
      O.TauFactor = 0.15;
      O.CommFactor = 0.6;
      O.DvInsert = 2900;
      O.DvPerYear = 100;
      $impl.SetFactors(O,pas.TsCatalog.MV(1.2,1.2,1.2,1.35,1.5,1.3,1,1.3,1));
      O.RadLevel = 3;
      O.RadLifeYears = 0.3;
      $impl.AddOrbit(S,O);
      O.$assign($impl.NewOrbit("jpolar","Jupiter polar orbit","Long loops over Jupiter's poles, like Juno.","Ducks under the worst of the radiation, so the spacecraft lasts. Superb for Jupiter itself, " + "but Europa is only glimpsed from a distance a few times."));
      O.AltKm = 5000;
      O.ApoKm = 8000000;
      O.IncDeg = 90;
      O.PeriodHr = 1270;
      O.EclipseFrac = 0.0;
      O.MaxEclipseHr = 0;
      O.Coverage = 0.2;
      O.CommFactor = 0.95;
      O.DvInsert = 1250;
      O.DvPerYear = 20;
      $impl.SetFactors(O,pas.TsCatalog.MV(0.5,0.5,0.5,0.3,0.6,0.4,1.5,1.2,1));
      O.RadLevel = 2;
      O.RadLifeYears = 7;
      $impl.AddOrbit(S,O);
      $impl.AddTransfer(S,"direct","Direct (2.7 years)","Straight to Jupiter. Needs an enormous amount of launch energy.",82,2.7,1,false);
      $impl.AddTransfer(S,"mega","Mars and Earth gravity assists (5.5 years)","Swing past Mars and then Earth to pick up speed. Halves the launch energy. Europa Clipper's route.",41,5.5,1,false);
      $impl.AddTransfer(S,"veega","Venus and Earth gravity assists (6.5 years)","Three planetary flybys, starting inward at Venus where it is twice as hot as at Earth. The smallest rocket of all, the longest wait. Galileo's route.",16,6.5,1,true);
      $impl.Offer(S,["sar","mag","plasma","spec_vnir","cam_hires","cam_ctx","tir","massspec","dust","uvs","radio"]);
      $impl.AddAnalog(S,"Europa Clipper","NASA","2024","Nine instruments, solar wings over 30 m across and a 3 m dish. It will make about 49 flybys from 2030.","https://science.nasa.gov/mission/europa-clipper/",6065,5200,9);
      $impl.AddAnalog(S,"Juno","NASA","2011","The first solar-powered spacecraft at Jupiter. Its electronics live in a 200 kg titanium vault.","https://science.nasa.gov/mission/juno/",3625,1130,9);
      $impl.AddAnalog(S,"Galileo","NASA","1989","Nuclear-powered. Its main antenna jammed, cutting the data rate ten-thousand-fold, yet it still discovered Europa's ocean.","https://science.nasa.gov/mission/galileo/",2562,1600,10);
      $impl.AddAnalog(S,"JUICE","ESA","2023","Europe's mission to Jupiter's icy moons, with 85 m2 of solar panels. It arrives in 2031.","https://www.esa.int/Science_Exploration/Space_Science/Juice",6070,1700,10);
      $impl.AddAnalog(S,"New Horizons","NASA","2006","A small, nuclear-powered probe launched so fast that it passed the Moon in nine hours.","https://science.nasa.gov/mission/new-horizons/",478,780,7);
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Juno's solar panels cover 60 m2, yet at Jupiter they make only about 500 W: less than a microwave oven uses.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Europa Clipper's solar wings span more than 30 m, longer than a basketball court.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Galileo's main antenna never opened. Engineers rescued the mission by teaching the spacecraft to compress its data.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Juno keeps its electronics inside a titanium vault with walls about a centimetre thick.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Europa Clipper flies past Europa again and again instead of orbiting it, to limit the radiation it soaks up.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"Voyager's nuclear batteries are still working nearly 50 years after launch.");
      pas.TsTypes.AddStr({p: S, get: function () {
          return this.p.Facts;
        }, set: function (v) {
          this.p.Facts = v;
        }},"A radio signal from Jupiter takes around 45 minutes to reach Earth.");
      $impl.AddScenario(S);
    };
  };
  $mod.$init = function () {
    $impl.BuildEarth();
    $impl.BuildMoon();
    $impl.BuildMars();
    $impl.BuildApophis();
    $impl.BuildEuropa();
    $mod.ApophisDays = 881;
    $mod.ApophisMissKm = 38011;
    $mod.ApophisVelKmS = 7.42;
    $mod.ApophisDate = "2029-04-13";
    $mod.EarthEventsSource = "";
    $impl.BuildFallbackWeather();
  };
},["Math","TsCatalog","TsFmt"]);
rtl.module("TsEngine",["System","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  rtl.recNewT(this,"TLaunchOption",function () {
    this.CapKg = 0.0;
    this.CostM = 0.0;
    this.Margin = 0.0;
    this.CanReach = false;
    this.Fits = false;
    this.Why = "";
    this.$eq = function (b) {
      return (this.CapKg === b.CapKg) && (this.CostM === b.CostM) && (this.Margin === b.Margin) && (this.CanReach === b.CanReach) && (this.Fits === b.Fits) && (this.Why === b.Why);
    };
    this.$assign = function (s) {
      this.CapKg = s.CapKg;
      this.CostM = s.CostM;
      this.Margin = s.Margin;
      this.CanReach = s.CanReach;
      this.Fits = s.Fits;
      this.Why = s.Why;
      return this;
    };
  });
  this.DifficultyCapMult = function (Df) {
    var Result = 0.0;
    var $tmp = Df;
    if ($tmp === 0) {
      Result = 1.2}
     else if ($tmp === 2) {
      Result = 0.9}
     else {
      Result = 1.0;
    };
    return Result;
  };
  this.NewDesign = function (AScenario, ADifficulty, ASandbox) {
    var Result = pas.TsTypes.TDesign.$new();
    var K = 0;
    var I = 0;
    var Near = false;
    var Far = false;
    Near = pas.TsScenarios.Scenarios[AScenario].NearEarth;
    Far = pas.TsScenarios.Scenarios[AScenario].SunAU > 3;
    Result.Scenario = AScenario;
    Result.Difficulty = ADifficulty;
    Result.Sandbox = ASandbox;
    Result.Orbit = 0;
    Result.Transfer = 0;
    for (K = 0; K <= 11; K++) Result.Part[K] = 0;
    Result.Part[0] = 1;
    if (Far) Result.Part[0] = 2;
    if (Near) {
      Result.Part[1] = 0}
     else if (Far || (pas.TsScenarios.Scenarios[AScenario].Id === "mars")) {
      Result.Part[1] = 3}
     else Result.Part[1] = 2;
    Result.Part[2] = 1;
    Result.Part[3] = 0;
    if (Near) {
      Result.Part[4] = 0}
     else Result.Part[4] = 1;
    Result.Part[5] = 0;
    if (Near) {
      Result.Part[6] = 0;
      Result.Part[7] = 1;
    } else {
      Result.Part[6] = 1;
      Result.Part[7] = 2;
    };
    Result.Part[8] = 0;
    Result.Part[9] = 0;
    Result.Part[10] = 1;
    Result.Part[11] = 0;
    Result.Launcher = -1;
    Result.Instr = rtl.arraySetLength(Result.Instr,false,rtl.length(pas.TsCatalog.Instruments));
    for (var $l = 0, $end = rtl.length(Result.Instr) - 1; $l <= $end; $l++) {
      I = $l;
      Result.Instr[I] = false;
    };
    if (Far) {
      Result.SolarM2 = 20}
     else if (pas.TsScenarios.Scenarios[AScenario].SunAU > 1.3) {
      Result.SolarM2 = 5}
     else if (Near) {
      Result.SolarM2 = 1.0}
     else Result.SolarM2 = 1.5;
    Result.RtgCount = 0;
    Result.BatteryWh = 300;
    Result.LifeYears = pas.TsScenarios.Scenarios[AScenario].DefaultLife;
    Result.ReservePct = 20;
    Result.Seed = 12345;
    return Result;
  };
  this.InstrumentOffered = function (AScenario, AInstr) {
    var Result = false;
    var I = 0;
    Result = false;
    for (var $l = 0, $end = rtl.length(pas.TsScenarios.Scenarios[AScenario].Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if (pas.TsScenarios.Scenarios[AScenario].Instruments[I] === pas.TsCatalog.Instruments[AInstr].Id) {
        Result = true;
        return Result;
      };
    };
    return Result;
  };
  this.LauncherCapacity = function (ALauncher, D, Why) {
    var Result = 0.0;
    var L = pas.TsTypes.TLauncher.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var C3 = 0.0;
    var BusCls = 0;
    Result = 0;
    Why.set("");
    if ((ALauncher < 0) || (ALauncher > (rtl.length(pas.TsCatalog.Launchers) - 1))) return Result;
    L.$assign(pas.TsCatalog.Launchers[ALauncher]);
    O.$assign(pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit]);
    BusCls = pas.TsCatalog.BusClassOf(pas.TsCatalog.Parts[0][D.Part[0]]);
    if (BusCls > L.MaxBus) {
      Why.set("A " + pas.TsTypes.BusClassName[BusCls] + " does not fit this launcher.");
      return Result;
    };
    var $tmp = O.LvMode;
    if ($tmp === 0) {
      Result = L.LeoKg}
     else if ($tmp === 1) {
      Result = L.SsoKg}
     else if ($tmp === 2) {
      Result = L.GtoKg}
     else {
      C3 = $mod.LaunchEnergy(D);
      if (L.C3ZeroKg > 0) Result = L.C3ZeroKg * Math.exp(-C3 / L.C3K);
      if (L.Rideshare && ((C3 > 15) || (D.Transfer !== 0))) {
        Result = 0;
        Why.set("No shared launch is going that way. A rideshare can only follow the main passenger's route.");
        return Result;
      };
    };
    if ((Result <= 0) && (Why.get() === "")) {
      if (L.Rideshare) {
        Why.set("Rideshare launches only go to sun-synchronous orbit or along a standard deep-space route.")}
       else Why.set("This rocket cannot deliver anything to " + $mod.LaunchTargetName(D) + ".");
    };
    return Result;
  };
  this.LauncherCost = function (ALauncher, D, WetKg) {
    var Result = 0.0;
    var L = pas.TsTypes.TLauncher.$new();
    Result = 0;
    if ((ALauncher < 0) || (ALauncher > (rtl.length(pas.TsCatalog.Launchers) - 1))) return Result;
    L.$assign(pas.TsCatalog.Launchers[ALauncher]);
    if (L.Rideshare) {
      if (pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit].LvMode === 3) {
        Result = 9}
       else Result = pas.TsTypes.MaxD(1.2,0.0065 * WetKg);
    } else Result = L.CostM;
    return Result;
  };
  this.LaunchOption = function (ALauncher, D, WetKg) {
    var Result = $mod.TLaunchOption.$new();
    var Why = "";
    Result.CapKg = $mod.LauncherCapacity(ALauncher,D,{get: function () {
        return Why;
      }, set: function (v) {
        Why = v;
      }});
    Result.Why = Why;
    Result.CostM = $mod.LauncherCost(ALauncher,D,WetKg);
    Result.CanReach = Result.CapKg > 0;
    Result.Fits = Result.CanReach && (WetKg <= Result.CapKg);
    if (Result.CanReach) {
      Result.Margin = (Result.CapKg - WetKg) / Result.CapKg}
     else Result.Margin = -1;
    return Result;
  };
  this.LinkRateMbps = function (D, DistAU, PointingTier) {
    var Result = 0.0;
    var Ant = pas.TsTypes.TPart.$new();
    var Band = pas.TsTypes.TPart.$new();
    var Tx = pas.TsTypes.TPart.$new();
    var Gnd = pas.TsTypes.TPart.$new();
    var D2 = 0.0;
    Ant.$assign(pas.TsCatalog.Parts[6][D.Part[6]]);
    Band.$assign(pas.TsCatalog.Parts[7][D.Part[7]]);
    Tx.$assign(pas.TsCatalog.Parts[8][D.Part[8]]);
    Gnd.$assign(pas.TsCatalog.Parts[9][D.Part[9]]);
    if (DistAU < 1.0e-6) DistAU = 1.0e-6;
    D2 = DistAU * DistAU;
    if (Band.Tier === 4) {
      Result = Band.A / D2}
     else Result = (0.0012 * Tx.A * Ant.A * Ant.A * Band.A * Gnd.C) / D2;
    if (Result > Band.B) Result = Band.B;
    if (Math.round(Band.D) > PointingTier) {
      Result = Result * 0.25}
     else if ((Ant.A >= 0.5) && (PointingTier < 1) && (Band.Tier < 4)) Result = Result * 0.3;
    return Result;
  };
  this.LaunchEnergy = function (D) {
    var Result = 0.0;
    Result = pas.TsScenarios.Scenarios[D.Scenario].Transfers[D.Transfer].C3 + pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit].C3;
    return Result;
  };
  this.LaunchTargetName = function (D) {
    var Result = "";
    var $tmp = pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit].LvMode;
    if ($tmp === 0) {
      Result = "low Earth orbit"}
     else if ($tmp === 1) {
      Result = "sun-synchronous orbit"}
     else if ($tmp === 2) {
      Result = "geostationary transfer orbit"}
     else {
      Result = "this escape route (launch energy C3 = " + pas.TsFmt.FmtNum($mod.LaunchEnergy(D),0) + " km2/s2)";
    };
    return Result;
  };
  this.InstrumentQuality = function (D, Alive, PointTier, Q) {
    var I = 0;
    var Therm = pas.TsTypes.TPart.$new();
    var Ant = pas.TsTypes.TPart.$new();
    var Band = pas.TsTypes.TPart.$new();
    var V = 0.0;
    Therm.$assign(pas.TsCatalog.Parts[3][D.Part[3]]);
    Ant.$assign(pas.TsCatalog.Parts[6][D.Part[6]]);
    Band.$assign(pas.TsCatalog.Parts[7][D.Part[7]]);
    Q.set(rtl.arraySetLength(Q.get(),0.0,rtl.length(pas.TsCatalog.Instruments)));
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      Q.get()[I] = 0;
      if ((I > (rtl.length(D.Instr) - 1)) || !D.Instr[I]) continue;
      if ((I <= (rtl.length(Alive) - 1)) && !Alive[I]) continue;
      if (!$mod.InstrumentOffered(D.Scenario,I)) continue;
      V = 1;
      if (pas.TsCatalog.Instruments[I].NeedsFinePointing && (PointTier < 1)) V = V * 0.4;
      if (pas.TsCatalog.Instruments[I].NeedsCooling && (Therm.Tier < 2)) V = V * 0.5;
      if (pas.TsCatalog.Instruments[I].NeedsHGA && ((Ant.A < 0.5) || (Band.Tier < 2))) V = V * 0.25;
      Q.get()[I] = V;
    };
  };
  this.MeasureCapability = function (D, Q) {
    var Result = rtl.arraySetLength(null,0.0,9);
    var M = 0;
    var I = 0;
    var J = 0;
    var N = 0;
    var Contrib = [];
    var Sum = 0.0;
    var Share = 0.0;
    var Tmp = 0.0;
    var O = pas.TsTypes.TOrbit.$new();
    O.$assign(pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit]);
    for (M = 0; M <= 8; M++) {
      Contrib = rtl.arraySetLength(Contrib,0.0,0);
      for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
        I = $l;
        if ((I <= (rtl.length(Q) - 1)) && (Q[I] > 0) && (pas.TsCatalog.Instruments[I].Value[M] > 0)) {
          N = rtl.length(Contrib);
          Contrib = rtl.arraySetLength(Contrib,0.0,N + 1);
          Contrib[N] = pas.TsCatalog.Instruments[I].Value[M] * Q[I];
        };
      };
      for (var $l1 = 0, $end1 = rtl.length(Contrib) - 1 - 1; $l1 <= $end1; $l1++) {
        I = $l1;
        for (var $l2 = I + 1, $end2 = rtl.length(Contrib) - 1; $l2 <= $end2; $l2++) {
          J = $l2;
          if (Contrib[J] > Contrib[I]) {
            Tmp = Contrib[I];
            Contrib[I] = Contrib[J];
            Contrib[J] = Tmp;
          };
        };
      };
      Sum = 0;
      Share = 1;
      for (var $l3 = 0, $end3 = rtl.length(Contrib) - 1; $l3 <= $end3; $l3++) {
        I = $l3;
        Sum = Sum + (Contrib[I] * Share);
        Share = Share * 0.5;
      };
      Result[M] = pas.TsTypes.MinD(110,Sum * O.Factor[M]);
    };
    return Result;
  };
  this.DataGenGbitDay = function (D, Alive) {
    var Result = 0.0;
    var I = 0;
    var Mbps = 0.0;
    Mbps = 0;
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if ((I <= (rtl.length(D.Instr) - 1)) && D.Instr[I] && $mod.InstrumentOffered(D.Scenario,I) && ((I > (rtl.length(Alive) - 1)) || Alive[I])) Mbps = Mbps + (pas.TsCatalog.Instruments[I].DataMbps * pas.TsCatalog.Instruments[I].Duty * pas.TsScenarios.Scenarios[D.Scenario].DataScale * pas.TsScenarios.Scenarios[D.Scenario].Orbits[D.Orbit].DataFactor);
    };
    Result = (Mbps * 86400) / 1000;
    return Result;
  };
  this.Analyze = function (D) {
    var Result = pas.TsTypes.TAnalysis.$new();
    var A = pas.TsTypes.TAnalysis.$new();
    var NoDead = [];
    var GP = 0.0;
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var Tr = pas.TsTypes.TTransfer.$new();
    var Bus = pas.TsTypes.TPart.$new();
    var Prop = pas.TsTypes.TPart.$new();
    var Adcs = pas.TsTypes.TPart.$new();
    var Therm = pas.TsTypes.TPart.$new();
    var Comp = pas.TsTypes.TPart.$new();
    var Shield = pas.TsTypes.TPart.$new();
    var Ant = pas.TsTypes.TPart.$new();
    var Band = pas.TsTypes.TPart.$new();
    var Tx = pas.TsTypes.TPart.$new();
    var Gnd = pas.TsTypes.TPart.$new();
    var Risk = pas.TsTypes.TPart.$new();
    var Sched = pas.TsTypes.TPart.$new();
    var L = pas.TsTypes.TLauncher.$new();
    var G = 0.0;
    var G06 = 0.0;
    var G07 = 0.0;
    var G08 = 0.0;
    var I = 0;
    var J = 0;
    var Cnt = 0;
    var Prot = 0;
    var K = 0;
    var M = 0;
    var Ins = pas.TsTypes.TInstrument.$new();
    var PayW = 0.0;
    var PayPeakW = 0.0;
    var PayCost = 0.0;
    var PayDev = 0.0;
    var GenMbps = 0.0;
    var AdcsKg = 0.0;
    var AdcsW = 0.0;
    var AdcsCost = 0.0;
    var CompKg = 0.0;
    var CompCost = 0.0;
    var ShieldKg = 0.0;
    var ShieldCost = 0.0;
    var ThermCost = 0.0;
    var HeaterW = 0.0;
    var ArrayKg = 0.0;
    var ArrayCost = 0.0;
    var BattKg = 0.0;
    var BattCost = 0.0;
    var RtgKgT = 0.0;
    var RtgCost = 0.0;
    var PropDry = 0.0;
    var PropCost = 0.0;
    var TankKg = 0.0;
    var BaseKg = 0.0;
    var DryNoTank = 0.0;
    var X = 0.0;
    var Denom = 0.0;
    var BaseW = 0.0;
    var CommW = 0.0;
    var TxDuty = 0.0;
    var Ecl = 0.0;
    var SepNeedW = 0.0;
    var SepHaveW = 0.0;
    var MidAU = 0.0;
    var DistAvg = 0.0;
    var DistMax = 0.0;
    var Dev = 0.0;
    var OpsYear = 0.0;
    var SlipCost = 0.0;
    var CapSum = 0.0;
    var PowerFactor = 0.0;
    var DataFactor = 0.0;
    var EffLife = 0.0;
    var LifeRad = 0.0;
    var FailRate = 0.0;
    var Best = 0.0;
    var SunShare = 0.0;
    var CapMult = 0.0;
    var Names = "";
    var BigName = "";
    var Why = "";
    var Late = false;
    var HasPrimary = false;
    var UsesSep = false;
    var Prim = 0;
    var SevCost = 0;
    function AddF(ASev, ACode, ATitle, AWhy, AFix, AOwner) {
      var Idx = 0;
      Idx = rtl.length(A.Findings);
      A.Findings = rtl.arraySetLength(A.Findings,pas.TsTypes.TFinding,Idx + 1);
      A.Findings[Idx].Sev = ASev;
      A.Findings[Idx].Code = ACode;
      A.Findings[Idx].Title = ATitle;
      A.Findings[Idx].Why = AWhy;
      A.Findings[Idx].Fix = AFix;
      A.Findings[Idx].Owner = AOwner;
      if (ASev === 3) {
        A.Blockers += 1}
       else if (ASev === 2) A.Warnings += 1;
    };
    Sc.$assign(pas.TsScenarios.Scenarios[D.Scenario]);
    O.$assign(Sc.Orbits[D.Orbit]);
    Tr.$assign(Sc.Transfers[D.Transfer]);
    Bus.$assign(pas.TsCatalog.Parts[0][D.Part[0]]);
    Prop.$assign(pas.TsCatalog.Parts[1][D.Part[1]]);
    Adcs.$assign(pas.TsCatalog.Parts[2][D.Part[2]]);
    Therm.$assign(pas.TsCatalog.Parts[3][D.Part[3]]);
    Comp.$assign(pas.TsCatalog.Parts[4][D.Part[4]]);
    Shield.$assign(pas.TsCatalog.Parts[5][D.Part[5]]);
    Ant.$assign(pas.TsCatalog.Parts[6][D.Part[6]]);
    Band.$assign(pas.TsCatalog.Parts[7][D.Part[7]]);
    Tx.$assign(pas.TsCatalog.Parts[8][D.Part[8]]);
    Gnd.$assign(pas.TsCatalog.Parts[9][D.Part[9]]);
    Risk.$assign(pas.TsCatalog.Parts[10][D.Part[10]]);
    Sched.$assign(pas.TsCatalog.Parts[11][D.Part[11]]);
    A.Findings = rtl.arraySetLength(A.Findings,pas.TsTypes.TFinding,0);
    A.MassLines = rtl.arraySetLength(A.MassLines,pas.TsTypes.TLine,0);
    A.PowerLines = rtl.arraySetLength(A.PowerLines,pas.TsTypes.TLine,0);
    A.CostLines = rtl.arraySetLength(A.CostLines,pas.TsTypes.TLine,0);
    A.Blockers = 0;
    A.Warnings = 0;
    A.LifeLimitWhy = "";
    UsesSep = Prop.Tier === 4;
    G = Bus.G;
    G06 = Math.pow(G,0.6);
    G07 = Math.pow(G,0.7);
    G08 = Math.pow(G,0.8);
    CapMult = $mod.DifficultyCapMult(D.Difficulty);
    A.PayloadKg = 0;
    PayW = 0;
    PayPeakW = 0;
    PayCost = 0;
    PayDev = 0;
    GenMbps = 0;
    Cnt = 0;
    NoDead = rtl.arraySetLength(NoDead,false,0);
    $mod.InstrumentQuality(D,NoDead,Adcs.Tier,{p: A, get: function () {
        return this.p.InstrQuality;
      }, set: function (v) {
        this.p.InstrQuality = v;
      }});
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if (A.InstrQuality[I] > 0) {
        Ins.$assign(pas.TsCatalog.Instruments[I]);
        Cnt += 1;
        A.PayloadKg = A.PayloadKg + Ins.MassKg;
        PayW = PayW + (Ins.PowerW * (0.2 + (0.8 * Ins.Duty)));
        PayPeakW = PayPeakW + Ins.PowerW;
        PayCost = PayCost + Ins.CostM;
        if (Ins.DevYears > PayDev) PayDev = Ins.DevYears;
        GenMbps = GenMbps + (Ins.DataMbps * Ins.Duty * Sc.DataScale * O.DataFactor);
      };
    };
    if (Cnt > 1) PayDev = PayDev + (0.08 * (Cnt - 1));
    A.InstrumentCount = Cnt;
    A.PointingTier = Adcs.Tier;
    AdcsKg = Adcs.MassKg * G * Risk.B;
    AdcsW = Adcs.PowerW * G08;
    AdcsCost = Adcs.CostM * G07 * Risk.A;
    CompKg = Comp.MassKg * Risk.B;
    CompCost = Comp.CostM * Risk.A;
    ShieldKg = Shield.MassKg * G;
    ShieldCost = Shield.CostM * G07;
    HeaterW = Sc.HeaterW * G07 * Therm.B;
    if (D.RtgCount > 0) HeaterW = HeaterW * 0.5;
    ThermCost = (Therm.CostM * G07) + Therm.E;
    ArrayKg = D.SolarM2 * 3.4;
    ArrayCost = 0;
    if (D.SolarM2 > 0) ArrayCost = (D.SolarM2 * 0.32) + 0.4;
    BattKg = D.BatteryWh / 130;
    BattCost = 0;
    if (D.BatteryWh > 0) BattCost = (D.BatteryWh * 0.0022) + 0.2;
    RtgKgT = D.RtgCount * 45;
    RtgCost = D.RtgCount * 95;
    if (G >= 1) {
      GP = G06}
     else GP = Math.pow(G,1.1);
    PropDry = Prop.MassKg * GP;
    BaseKg = Bus.MassKg + A.PayloadKg + AdcsKg + CompKg + ShieldKg + Ant.MassKg + Band.MassKg + Tx.MassKg + Therm.MassKg + ArrayKg + BattKg + RtgKgT + PropDry;
    DryNoTank = BaseKg * (1 + Therm.A + 0.07);
    A.DvInsert = O.DvInsert * Tr.DvFactor;
    if (UsesSep) A.DvInsert = A.DvInsert * Sc.SepDvFactor;
    A.DvKeep = O.DvPerYear * D.LifeYears;
    A.DvDisposal = 0;
    if (O.NeedsDeorbit && (Prop.Tier > 0)) A.DvDisposal = 160;
    A.DvNeed = (A.DvInsert + A.DvKeep + A.DvDisposal) * (1 + 0.1);
    A.PropFeasible = true;
    A.PropKg = 0;
    TankKg = 0;
    if ((Prop.Tier > 0) && (A.DvNeed > 0)) {
      X = Math.exp(A.DvNeed / (Prop.A * 9.80665)) - 1;
      Denom = 1 - (Prop.B * X);
      if (Denom <= 0.05) {
        A.PropFeasible = false;
        A.PropKg = DryNoTank * 20;
      } else A.PropKg = (DryNoTank * X) / Denom;
      TankKg = Prop.B * A.PropKg;
    };
    A.DryKg = DryNoTank + TankKg;
    A.WetKg = A.DryKg + A.PropKg;
    PropCost = 0;
    if (Prop.Tier > 0) PropCost = ((Prop.CostM * GP) + (Prop.E * A.PropKg)) * Risk.A;
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Structure",Bus.MassKg);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Instruments",A.PayloadKg);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Power system",ArrayKg + BattKg + RtgKgT);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Communications",Ant.MassKg + Band.MassKg + Tx.MassKg);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Avionics and pointing",AdcsKg + CompKg + ShieldKg);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Thermal and cabling",Therm.MassKg + (BaseKg * (Therm.A + 0.07)));
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Engines and tanks",PropDry + TankKg);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.MassLines;
      }, set: function (v) {
        this.p.MassLines = v;
      }},"Propellant",A.PropKg);
    A.LvCapKg = 0;
    A.MassMargin = -1;
    A.CostLaunch = 0;
    if (D.Launcher >= 0) {
      A.LvCapKg = $mod.LauncherCapacity(D.Launcher,D,{get: function () {
          return Why;
        }, set: function (v) {
          Why = v;
        }});
      A.CostLaunch = $mod.LauncherCost(D.Launcher,D,A.WetKg);
      if (A.LvCapKg > 0) A.MassMargin = (A.LvCapKg - A.WetKg) / A.LvCapKg;
    };
    if (Sc.NearEarth) {
      DistAvg = O.RangeKm / 1.495978707E8;
      DistMax = DistAvg;
      A.ContactHr = Gnd.B * O.CommFactor;
    } else {
      DistAvg = (Sc.EarthMinAU + Sc.EarthMaxAU) / 2;
      DistMax = Sc.EarthMaxAU;
      A.ContactHr = Gnd.A * O.CommFactor;
    };
    if (A.ContactHr > 24) A.ContactHr = 24;
    A.ContactHr = A.ContactHr * Band.C;
    A.RateAvgMbps = $mod.LinkRateMbps(D,DistAvg,Adcs.Tier);
    A.RateMinMbps = $mod.LinkRateMbps(D,DistMax,Adcs.Tier);
    A.DownGbitDay = (A.RateAvgMbps * A.ContactHr * 3600) / 1000;
    A.GenGbitDay = (GenMbps * 86400) / 1000;
    if (A.GenGbitDay > 0) {
      A.DataReturn = pas.TsTypes.MinD(1,A.DownGbitDay / A.GenGbitDay)}
     else A.DataReturn = 1;
    A.StorageGbit = Comp.A;
    if (A.GenGbitDay > 0) {
      A.StorageDays = A.StorageGbit / A.GenGbitDay}
     else A.StorageDays = 999;
    A.LightDelayMin = (DistAvg * 499) / 60;
    TxDuty = A.ContactHr / 24;
    A.SolarW = (D.SolarM2 * 250) / (Sc.SunAU * Sc.SunAU);
    if (Sc.SunAU > 3) A.SolarW = A.SolarW * 0.85;
    A.RtgW = D.RtgCount * 110;
    A.GenW = A.SolarW + A.RtgW;
    Ecl = O.EclipseFrac;
    A.GenAvgW = A.RtgW + ((A.SolarW * (1 - Ecl)) / ((1 - Ecl) + (Ecl / 0.85)));
    BaseW = Bus.PowerW + AdcsW + Comp.PowerW + pas.TsTypes.MinD(Band.PowerW,10) + Therm.PowerW + HeaterW;
    CommW = Tx.PowerW * TxDuty;
    if (Band.Tier === 4) CommW = (Band.PowerW - 10) * TxDuty;
    A.LoadAvgW = BaseW + PayW + CommW;
    A.LoadPeakW = BaseW + PayPeakW + Tx.PowerW;
    if (A.LoadAvgW > 0) {
      A.PowerMargin = (A.GenAvgW - A.LoadAvgW) / A.LoadAvgW}
     else A.PowerMargin = 0;
    A.BatteryNeedWh = 0;
    if ((O.MaxEclipseHr > 0) && (A.LoadAvgW > A.RtgW)) A.BatteryNeedWh = ((A.LoadAvgW - A.RtgW) * O.MaxEclipseHr) / 0.6;
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.PowerLines;
      }, set: function (v) {
        this.p.PowerLines = v;
      }},"Spacecraft housekeeping",Bus.PowerW + Comp.PowerW + pas.TsTypes.MinD(Band.PowerW,10));
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.PowerLines;
      }, set: function (v) {
        this.p.PowerLines = v;
      }},"Pointing",AdcsW);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.PowerLines;
      }, set: function (v) {
        this.p.PowerLines = v;
      }},"Heaters and coolers",Therm.PowerW + HeaterW);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.PowerLines;
      }, set: function (v) {
        this.p.PowerLines = v;
      }},"Instruments",PayW);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.PowerLines;
      }, set: function (v) {
        this.p.PowerLines = v;
      }},"Transmitter (averaged)",CommW);
    A.DevYears = Bus.DevYears + PayDev + Prop.DevYears + Therm.DevYears + Comp.DevYears + Shield.DevYears + Band.DevYears + Adcs.DevYears + Ant.DevYears + Risk.D;
    if (D.RtgCount > 0) A.DevYears = A.DevYears + 1.0;
    A.DevYears = pas.TsTypes.MaxD(0.75,A.DevYears * Sched.A);
    A.LaunchYear = A.DevYears;
    if (Sc.WindowYears > 0) {
      A.LaunchYear = Sc.WindowYears;
      K = 0;
      while ((A.LaunchYear < (A.DevYears - 0.001)) && (K < 20)) {
        A.LaunchYear = A.LaunchYear + Sc.WindowPeriod;
        K += 1;
      };
    };
    A.CruiseYears = Tr.CruiseYears + O.ExtraYears;
    if (UsesSep) A.CruiseYears = A.CruiseYears + Sc.SepExtraYears;
    A.ArriveYear = A.LaunchYear + A.CruiseYears;
    if (Sc.ArriveBy) {
      Late = A.ArriveYear > (Sc.DeadlineYears + 0.001)}
     else Late = A.LaunchYear > (Sc.DeadlineYears + 0.001);
    A.MissedDeadline = Late;
    A.SlipYears = 0;
    if (Late && !Sc.ArriveBy) A.SlipYears = A.LaunchYear - Sc.DeadlineYears;
    A.LifeYears = D.LifeYears;
    Prot = Comp.Tier + Shield.Tier;
    A.RadExposure = O.RadLevel - Prot;
    if (A.RadExposure < 0) A.RadExposure = 0;
    A.LifeLimitYears = 1000;
    if (O.RadLifeYears > 0) {
      LifeRad = O.RadLifeYears;
      if (Prot > O.RadLevel) LifeRad = LifeRad * (1 + (0.8 * (Prot - O.RadLevel)));
      for (var $l1 = 1, $end1 = A.RadExposure; $l1 <= $end1; $l1++) {
        J = $l1;
        LifeRad = LifeRad * 0.4;
      };
      if (LifeRad < A.LifeLimitYears) {
        A.LifeLimitYears = LifeRad;
        A.LifeLimitWhy = "radiation damage to the electronics";
      };
    };
    if ((O.DragLifeYears > 0) && (Prop.Tier === 0) && (O.DragLifeYears < A.LifeLimitYears)) {
      A.LifeLimitYears = O.DragLifeYears;
      A.LifeLimitWhy = "air drag pulling the orbit down";
    };
    EffLife = pas.TsTypes.MinD(D.LifeYears,A.LifeLimitYears);
    Prim = pas.TsScenarios.PrimaryMeasure(Sc);
    HasPrimary = false;
    for (var $l2 = 0, $end2 = rtl.length(pas.TsCatalog.Instruments) - 1; $l2 <= $end2; $l2++) {
      I = $l2;
      if ((A.InstrQuality[I] > 0) && (pas.TsCatalog.Instruments[I].Value[Prim] >= 30)) HasPrimary = true;
    };
    A.Capability = $mod.MeasureCapability(D,A.InstrQuality);
    CapSum = 0;
    for (M = 0; M <= 8; M++) CapSum = CapSum + ((Sc.Weight[M] * A.Capability[M]) / 100);
    CapSum = CapSum * O.Coverage;
    A.ScienceMaxPct = (100 * CapSum) / Sc.FullScience;
    PowerFactor = 1;
    if (A.LoadAvgW > 0) PowerFactor = pas.TsTypes.Clamp(A.GenAvgW / A.LoadAvgW,0,1);
    DataFactor = Math.pow(pas.TsTypes.MaxD(0.0004,A.DataReturn),0.7);
    A.TauYears = (Sc.TauYears * O.TauFactor) / pas.TsTypes.MaxD(0.03,PowerFactor * DataFactor);
    A.SciencePct = A.ScienceMaxPct * (1 - Math.exp(-EffLife / A.TauYears));
    if (Late && Sc.ArriveBy) A.SciencePct = A.SciencePct * Sc.LateFactor;
    FailRate = (1 - Bus.F) * Risk.C * Sched.C;
    if (A.RadExposure === 1) {
      FailRate = FailRate + 0.5}
     else if (A.RadExposure === 2) {
      FailRate = FailRate + 2.0}
     else if (A.RadExposure >= 3) FailRate = FailRate + 6.0;
    if ((Adcs.Tier > 0) && (Prop.Tier === 0) && !Sc.NearEarth) FailRate = FailRate + 0.4;
    if (Sc.ColdWorld && (Therm.Tier < 1)) FailRate = FailRate + 0.6;
    if (Tr.HotFlyby && (Therm.Tier < 1)) FailRate = FailRate + 0.4;
    A.AnomalyRate = FailRate;
    A.FatalShare = 0.22;
    if (Risk.Tier === 2) A.FatalShare = 0.11;
    A.YearSurvival = pas.TsTypes.Clamp(Math.exp(-FailRate * A.FatalShare),0.02,0.999);
    A.LaunchSuccess = 1;
    if (D.Launcher >= 0) A.LaunchSuccess = pas.TsCatalog.Launchers[D.Launcher].Reliability;
    if (D.Difficulty === 0) A.LaunchSuccess = 1;
    A.InsertSuccess = 1 - O.InsertRisk;
    if ((A.DvInsert > 200) && (Prop.Tier > 0)) A.InsertSuccess = A.InsertSuccess * Prop.D;
    A.SuccessProb = A.LaunchSuccess * A.InsertSuccess * Math.pow(A.YearSurvival,A.CruiseYears + EffLife);
    A.CostHardware = (Bus.CostM * Risk.A) + PayCost + AdcsCost + CompCost + ShieldCost + Ant.CostM + Band.CostM + Tx.CostM + ThermCost + ArrayCost + BattCost + RtgCost + PropCost;
    A.CostWraps = A.CostHardware * 0.23;
    Dev = (A.CostHardware + A.CostWraps) * Sched.B;
    OpsYear = Bus.E + Gnd.CostM + (0.6 * Cnt);
    A.CostOps = (OpsYear * D.LifeYears) + (0.5 * OpsYear * A.CruiseYears);
    SlipCost = A.SlipYears * 0.08 * Dev;
    A.CostReserve = (Dev * D.ReservePct) / 100;
    A.CostTotal = Dev + A.CostLaunch + A.CostOps + A.CostReserve + SlipCost;
    A.CapM = Sc.CostCapM * CapMult;
    A.CostMargin = (A.CapM - A.CostTotal) / A.CapM;
    A.DevCostM = Dev;
    A.OpsPerYearM = OpsYear;
    A.SlipCostM = SlipCost;
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Spacecraft bus",Bus.CostM * Risk.A * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Instruments",PayCost * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Power system",(ArrayCost + BattCost + RtgCost) * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Propulsion",PropCost * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Comms and avionics",(AdcsCost + CompCost + ShieldCost + Ant.CostM + Band.CostM + Tx.CostM + ThermCost) * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Management, assembly and test",A.CostWraps * Sched.B);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Launch",A.CostLaunch);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Operations",A.CostOps);
    pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Reserves",A.CostReserve);
    if (SlipCost > 0) pas.TsTypes.AddLine({p: A, get: function () {
        return this.p.CostLines;
      }, set: function (v) {
        this.p.CostLines = v;
      }},"Cost of delay",SlipCost);
    SunShare = 1 / (Sc.SunAU * Sc.SunAU);
    if (Cnt === 0) AddF(3,"NO_INSTR","No science instruments","The instruments are the reason the mission exists. Without them this is a very expensive paperweight.","Open Payload and choose at least one instrument that serves the objective.",1);
    if (Cnt > Math.round(Bus.C)) AddF(3,"INSTR_COUNT","Too many instruments for this bus","A " + Bus.Name + " has mounting points, power feeds and data ports for " + pas.SysUtils.IntToStr(Math.round(Bus.C)) + " instruments. You have chosen " + pas.SysUtils.IntToStr(Cnt) + ".","Remove an instrument, or move up to a bigger spacecraft bus.",2);
    if (A.PayloadKg > Bus.B) AddF(3,"PAYLOAD_MASS","Payload too heavy for this bus","A " + Bus.Name + " can carry " + pas.TsFmt.FmtMass(Bus.B) + " of instruments. Yours add up to " + pas.TsFmt.FmtMass(A.PayloadKg) + ".","Drop the heaviest instrument, or choose a bigger bus.",2);
    Names = "";
    for (var $l3 = 0, $end3 = rtl.length(pas.TsCatalog.Instruments) - 1; $l3 <= $end3; $l3++) {
      I = $l3;
      if ((A.InstrQuality[I] > 0) && (pas.TsCatalog.Instruments[I].MinBus > Bus.Tier)) {
        if (Names !== "") Names = Names + ", ";
        Names = Names + pas.TsCatalog.Instruments[I].Name;
      };
    };
    if (Names !== "") AddF(3,"INSTR_BUS","Instrument does not fit this bus","Too large for a " + Bus.Name + ": " + Names + ".","Choose a bigger bus or a smaller instrument.",1);
    if (A.DryKg > Bus.A) AddF(3,"DRY_LIMIT","Too much equipment for the structure","The frame of a " + Bus.Name + " is rated for " + pas.TsFmt.FmtMass(Bus.A) + " of equipment. You have " + pas.TsFmt.FmtMass(A.DryKg) + " before any propellant.","Remove equipment or choose a bigger bus.",2);
    if (D.SolarM2 > (Bus.D + 0.001)) AddF(3,"ARRAY_LIMIT","Solar array too large for this bus","A " + Bus.Name + " can deploy at most " + pas.TsFmt.FmtNum(Bus.D,1) + " m2 of panels. You have " + pas.TsFmt.FmtNum(D.SolarM2,1) + " m2.","Shrink the array, cut power use, or choose a bigger bus.",2);
    if ((D.RtgCount > 0) && !Sc.AllowRTG) AddF(3,"RTG_NA","Nuclear power is not approved for this mission","Plutonium-238 is scarce and is reserved for places where sunlight is too weak. Here solar panels work.","Remove the RTG and use solar panels.",0);
    if (A.GenW <= 0) {
      AddF(3,"NO_POWER","No power source","There are no solar panels and no nuclear battery. Nothing on board can switch on.","Add solar array area in Bus and Power.",2)}
     else if (A.GenAvgW < A.LoadAvgW) {
      AddF(3,"POWER_SHORT","Not enough power","Averaged over an orbit the spacecraft makes " + pas.TsFmt.FmtPower(A.GenAvgW) + " but needs " + pas.TsFmt.FmtPower(A.LoadAvgW) + ". Sunlight here is " + pas.TsFmt.FmtPct(SunShare) + " of what Earth gets, and " + pas.TsFmt.FmtPct(Ecl) + " of each orbit is in shadow.","Add solar array area, remove a power-hungry instrument or choose a smaller transmitter.",2)}
     else if (A.PowerMargin < 0.2) {
      AddF(2,"POWER_THIN","Thin power margin (" + pas.TsFmt.FmtPct(A.PowerMargin) + ")","Solar panels fade a few percent every year and equipment usually draws more than planned. NASA teams aim for about 30 % spare at this stage.","Add a little solar array area.",2)}
     else if (A.PowerMargin > 1.5) AddF(1,"POWER_BIG","Power system is oversized","You make " + pas.TsFmt.FmtPower(A.GenAvgW) + " and need " + pas.TsFmt.FmtPower(A.LoadAvgW) + ". The spare panels cost mass and money that could buy science.","Trim the array, or spend the power on another instrument or a stronger transmitter.",2);
    if ((A.BatteryNeedWh > 0) && (D.BatteryWh < A.BatteryNeedWh)) {
      AddF(3,"BATTERY","Battery too small for the dark","The longest eclipse here lasts " + pas.TsFmt.FmtNum(O.MaxEclipseHr,1) + " hours. Staying alive through it takes about " + pas.TsFmt.FmtNum(A.BatteryNeedWh,0) + " Wh. You carry " + pas.TsFmt.FmtNum(D.BatteryWh,0) + " Wh.","Add battery capacity, or cut power use.",2)}
     else if ((A.BatteryNeedWh > 0) && (D.BatteryWh < (A.BatteryNeedWh * 1.25))) AddF(2,"BATTERY_THIN","Battery has almost no spare capacity","Batteries lose capacity with every charge cycle. You carry " + pas.TsFmt.FmtNum(D.BatteryWh,0) + " Wh and need " + pas.TsFmt.FmtNum(A.BatteryNeedWh,0) + " Wh on day one.","Carry at least a quarter more than you need.",2);
    if ((Math.round(Adcs.A) === 1) && !(Sc.NearEarth && (O.AltKm < 2000))) AddF(3,"ADCS_MTQ","Magnetorquers will not work here","They turn the spacecraft by pushing against a planet's magnetic field. Out here there is almost no field to push against.","Choose reaction wheels.",2);
    if ((Adcs.Tier > 0) && (Prop.Tier === 0) && !Sc.NearEarth) AddF(2,"ADCS_DESAT","Reaction wheels have no way to unload","Wheels slowly spin faster as they fight sunlight pressure. Without thrusters to reset them they reach top speed and pointing is lost.","Add any thrusters, even cold gas.",2);
    Names = "";
    for (var $l4 = 0, $end4 = rtl.length(pas.TsCatalog.Instruments) - 1; $l4 <= $end4; $l4++) {
      I = $l4;
      if ((A.InstrQuality[I] > 0) && pas.TsCatalog.Instruments[I].NeedsFinePointing && (Adcs.Tier < 1)) Names = Names + pas.TsCatalog.Instruments[I].Name + " ";
    };
    if (Names !== "") AddF(2,"POINT_INSTR","Pictures will be blurred",Names + "needs a very steady spacecraft. With coarse pointing it works at 40 %.","Fit reaction wheels and a star tracker.",2);
    Names = "";
    for (var $l5 = 0, $end5 = rtl.length(pas.TsCatalog.Instruments) - 1; $l5 <= $end5; $l5++) {
      I = $l5;
      if ((A.InstrQuality[I] > 0) && pas.TsCatalog.Instruments[I].NeedsCooling && (Therm.Tier < 2)) Names = Names + pas.TsCatalog.Instruments[I].Name + " ";
    };
    if (Names !== "") AddF(2,"COOLING","Infrared detector is too warm",Names + "has a detector that must be far colder than the spacecraft. Without a cryocooler it works at half sensitivity.","Choose thermal control with a cryocooler, or swap the instrument.",2);
    for (var $l6 = 0, $end6 = rtl.length(pas.TsCatalog.Instruments) - 1; $l6 <= $end6; $l6++) {
      I = $l6;
      if ((A.InstrQuality[I] > 0) && pas.TsCatalog.Instruments[I].NeedsHGA && ((Ant.A < 0.5) || (Band.Tier < 2))) AddF(2,"RADIO_HGA","Radio science needs a better radio","Gravity is measured from tiny shifts in the radio signal. That needs a dish antenna and X-band or better. Working at 25 %.","Fit a dish and X-band or Ka-band, or drop the radio science package.",3);
    };
    if (Sc.ColdWorld && (Therm.Tier < 1)) AddF(2,"THERMAL_COLD","Passive thermal control is not enough here","The Sun delivers only " + pas.TsFmt.FmtPct(SunShare) + " of the warmth it gives at Earth. Blankets alone cannot keep the propellant and electronics from freezing.","Choose active thermal control.",2);
    if (Tr.HotFlyby && (Therm.Tier < 1)) AddF(2,"THERMAL_HOT","This route passes Venus","At Venus sunlight is twice as strong as at Earth. A spacecraft built for the cold of deep space needs a way to dump that heat.","Choose active thermal control, or a route that does not go inward.",2);
    if (A.RadExposure === 1) {
      AddF(2,"RAD","Electronics are exposed to radiation","Beyond Earth's magnetic shield, particles from the Sun and deep space flip bits and slowly damage chips. Expect an extra fault about every two years, and roughly a 10 % higher chance of losing the mission each year.","Use a radiation-tolerant or hardened computer, or add shielding.",2)}
     else if (A.RadExposure >= 2) AddF(2,"RAD","Radiation will destroy the electronics","This is one of the harshest radiation environments in the solar system, and the electronics are far too lightly protected. They are unlikely to last a year.","Fit a hardened computer and a radiation vault, or pick an orbit that stays out of the belts.",2);
    if (A.LifeLimitYears < (D.LifeYears - 0.01)) AddF(2,"LIFE_LIMIT","Mission will end early, after about " + pas.TsFmt.FmtYears(A.LifeLimitYears),"You planned " + pas.TsFmt.FmtYears(D.LifeYears) + ", but " + A.LifeLimitWhy + " will stop the spacecraft first. You would still pay for the full plan.","Fix the cause, or plan a shorter mission and save the operations cost.",3);
    if ((Prop.Tier === 0) && (A.DvInsert > 0)) {
      AddF(3,"PROP_NEEDED","This orbit needs an engine",'Reaching "' + O.Name + '" takes a speed change of ' + pas.TsFmt.FmtDv(A.DvInsert) + " after the rocket lets go. The spacecraft has no propulsion.","Add a propulsion system.",2)}
     else if (!A.PropFeasible) AddF(3,"PROP_RUNAWAY","The rocket equation says no","A speed change of " + pas.TsFmt.FmtDv(A.DvNeed) + " with this engine needs more propellant than any tank could hold: " + "every kilogram of fuel needs more fuel to carry it, and the demand grows exponentially.","Use a more efficient engine, choose an orbit or route that needs less speed change, or shorten the mission.",2);
    if (UsesSep && !Sc.AllowSEP) {
      AddF(3,"SEP_NA","Electric propulsion cannot do this job","Ion engines push too gently to brake into orbit here, and there is too little sunlight to run them.","Use a bipropellant engine.",2)}
     else if (UsesSep) {
      MidAU = (1 + Sc.SunAU) / 2;
      SepNeedW = Prop.C * G08;
      SepHaveW = ((D.SolarM2 * 250) / (MidAU * MidAU)) + A.RtgW;
      if (SepHaveW < SepNeedW) AddF(3,"SEP_POWER","Not enough power for the ion engine","The engine needs " + pas.TsFmt.FmtPower(SepNeedW) + " while thrusting. On the way out the panels give about " + pas.TsFmt.FmtPower(SepHaveW) + ".","Add solar array area, or use a chemical engine.",2);
    };
    if ((O.DragLifeYears > 0) && (Prop.Tier === 0) && (O.DragLifeYears >= D.LifeYears) && (O.DragLifeYears < 10)) AddF(1,"DRAG","Orbit decays in about " + pas.TsFmt.FmtYears(O.DragLifeYears),"With no engine, thin air at this height slowly pulls the satellite down. That is long enough for your plan, and it tidies the satellite away afterwards.","Nothing to do unless you want a longer mission.",3);
    if (O.NeedsDeorbit && (Prop.Tier === 0)) AddF(2,"DEORBIT","No plan to remove the satellite","At " + pas.TsFmt.FmtNum(O.AltKm,0) + " km a dead satellite stays up for centuries as space junk. Operators are expected to remove it within 25 years.","Add propulsion: the disposal burn is then budgeted automatically.",0);
    if (D.Launcher < 0) {
      AddF(3,"LV_NONE","No launch vehicle chosen","The spacecraft weighs " + pas.TsFmt.FmtMass(A.WetKg) + " fuelled and has no ride.","Open Launch and choose a rocket that can lift it.",0)}
     else {
      L.$assign(pas.TsCatalog.Launchers[D.Launcher]);
      if (A.LvCapKg <= 0) {
        AddF(3,"LV_REACH",L.Name + " cannot fly this mission",Why,"Choose a different launch vehicle or a different orbit.",0)}
       else if (A.WetKg > A.LvCapKg) {
        AddF(3,"LV_HEAVY","Too heavy for " + L.Name,"Fuelled, the spacecraft weighs " + pas.TsFmt.FmtMass(A.WetKg) + ". " + L.Name + " can send " + pas.TsFmt.FmtMass(A.LvCapKg) + " to " + $mod.LaunchTargetName(D) + ".","Choose a bigger rocket or a lower-energy route, or shed mass. Every kilogram of equipment you remove also removes the fuel needed to carry it.",0)}
       else if (A.MassMargin < 0.10) {
        AddF(2,"LV_THIN","Launch mass margin only " + pas.TsFmt.FmtPct(A.MassMargin),"Spacecraft almost always get heavier as they are built, often by 10 to 25 %. With this little spare, any growth means cutting something later.","Shed some mass or choose a slightly bigger rocket.",2)}
       else if ((A.MassMargin > 0.75) && !L.Rideshare) AddF(1,"LV_BIG","Rocket is much bigger than needed","You are using " + pas.TsFmt.FmtPct(1 - A.MassMargin) + " of what " + L.Name + " can lift. A smaller rocket might save money.","Compare the cheaper launchers.",0);
      if (L.Rideshare) AddF(1,"RIDESHARE","Rideshare: you do not pick the date","You fly when the main passenger is ready. If they slip, you wait and pay your team in the meantime.","Accept the risk, or buy a dedicated rocket.",0);
    };
    if ((Band.Tier === 0) && !Sc.NearEarth) AddF(3,"UHF_DEEP","UHF cannot reach Earth from here","UHF is a short-range band. From this distance the signal would be lost in the noise.","Choose S-band, X-band or better.",3);
    if (Math.round(Band.D) > Adcs.Tier) {
      AddF(2,"POINT_COMM","Radio beam needs steadier pointing",Band.Name + " squeezes the signal into a very narrow beam. This attitude control cannot hold it on Earth, so three quarters of the signal is lost.","Upgrade attitude control, or use a wider-beam band.",3)}
     else if ((Ant.A >= 0.5) && (Adcs.Tier < 1) && (Band.Tier < 4)) AddF(2,"POINT_DISH","Dish antenna needs steadier pointing","A dish only works when it points at Earth. With coarse pointing most of the signal misses.","Fit reaction wheels, or use a patch antenna.",3);
    if ((Cnt > 0) && (A.GenGbitDay > 0) && (A.DataReturn < 0.8)) AddF(2,"DATA","Data bottleneck: only " + pas.TsFmt.FmtPct(A.DataReturn) + " gets home","The instruments record " + pas.TsFmt.FmtData(A.GenGbitDay) + " a day, but the link carries only " + pas.TsFmt.FmtData(A.DownGbitDay) + " a day (" + pas.TsFmt.FmtRate(A.RateAvgMbps) + " for " + pas.TsFmt.FmtNum(A.ContactHr,1) + " hours). The rest is overwritten.","Use a bigger dish, a stronger transmitter, a higher band or more ground time. Or carry fewer data-hungry instruments.",3);
    if ((Cnt > 0) && (A.StorageDays < 0.5)) AddF(2,"STORAGE","Recorder fills in " + pas.TsFmt.FmtNum(A.StorageDays * 24,1) + " hours","The spacecraft can only talk to Earth during contacts. Between them it must store everything it records.","Choose a computer with more storage.",3);
    if (A.CostTotal > A.CapM) {
      BigName = "";
      Best = 0;
      for (var $l7 = 0, $end7 = rtl.length(A.CostLines) - 1; $l7 <= $end7; $l7++) {
        I = $l7;
        if (A.CostLines[I].Value > Best) {
          Best = A.CostLines[I].Value;
          BigName = A.CostLines[I].Name;
        };
      };
      SevCost = 3;
      if (D.Sandbox) SevCost = 1;
      AddF(SevCost,"COST_OVER","Over the cost cap by " + pas.TsFmt.FmtMoney(A.CostTotal - A.CapM),"The plan costs " + pas.TsFmt.FmtMoney(A.CostTotal) + " against a cap of " + pas.TsFmt.FmtMoney(A.CapM) + ". The biggest item is " + BigName + " at " + pas.TsFmt.FmtMoney(Best) + ". A mission that cannot show it fits the cap is not approved.","Look for the cheapest thing that still meets the objective: fewer instruments, a smaller bus, a cheaper rocket, a shorter mission or less ground time.",0);
    };
    if ((D.ReservePct < 15) && !D.Sandbox) AddF(2,"RESERVE_LOW","Reserves are only " + pas.TsFmt.FmtNum(D.ReservePct,0) + " %","Something always goes wrong during development. NASA expects about 25 % held back when a mission is confirmed.","Raise the reserves, even if it means flying a little less.",0);
    if (Late && Sc.ArriveBy) {
      AddF(2,"LATE","You will arrive after the flyby","Building takes " + pas.TsFmt.FmtYears(A.DevYears) + " and the trip " + pas.TsFmt.FmtYears(A.CruiseYears) + ", so you arrive in " + pas.TsFmt.FmtYears(A.ArriveYear) + ". The flyby is in " + pas.TsFmt.FmtYears(Sc.DeadlineYears) + ". You would miss the main event and score " + pas.TsFmt.FmtPct(Sc.LateFactor) + " of the science.","Build something simpler, speed up the schedule or take a faster route.",0)}
     else if (Late) {
      AddF(2,"LATE","Too slow for the deadline","The spacecraft will be ready to launch in " + pas.TsFmt.FmtYears(A.LaunchYear) + ". The announcement asks for launch within " + pas.TsFmt.FmtYears(Sc.DeadlineYears) + ". The delay costs about " + pas.TsFmt.FmtMoney(SlipCost) + " in salaries while the team waits.","Simplify the design, or pay for an accelerated schedule.",0)}
     else if ((Sc.WindowYears > 0) && ((A.LaunchYear - A.DevYears) > 0.5)) AddF(1,"WINDOW","Waiting " + pas.TsFmt.FmtYears(A.LaunchYear - A.DevYears) + " for the launch window","The spacecraft will be ready in " + pas.TsFmt.FmtYears(A.DevYears) + ", but the planets next line up in " + pas.TsFmt.FmtYears(A.LaunchYear) + ".","You have time to spare: you could afford a standard schedule or more testing.",0);
    if (D.LifeYears < (Sc.MinLife - 0.001)) AddF(2,"LIFE_MIN","Planned mission is shorter than required","The announcement asks for at least " + pas.TsFmt.FmtYears(Sc.MinLife) + " of science operations.","Extend the planned mission.",3);
    if ((Cnt > 0) && (O.Coverage < 0.5)) AddF(2,"COVERAGE","This orbit reaches only " + pas.TsFmt.FmtPct(O.Coverage) + " of the targets",O.Why,"Choose an orbit that passes over what you came to study.",1);
    if ((Cnt > 0) && !HasPrimary) AddF(2,"PRIMARY","Nothing on board measures " + pas.TsTypes.MeasureName[Prim],"That is the main objective of this mission. " + pas.TsTypes.MeasureHint[Prim],"Add an instrument that is strong in " + pas.TsTypes.MeasureName[Prim] + ".",1);
    if ((Cnt > 0) && (A.SciencePct < Sc.ThresholdPct)) AddF(2,"SCI_LOW","Predicted science is below the minimum","This design should return about " + pas.TsFmt.FmtNum(A.SciencePct,0) + " % of the full science goal. Below " + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " % the mission does not count as a success.","Check the other warnings: science is lost through a poor orbit, missing instruments, too little power, a data bottleneck or a short life.",1);
    if ((A.Blockers === 0) && (A.SuccessProb < 0.6)) AddF(2,"RISK","Only a " + pas.TsFmt.FmtPct(A.SuccessProb) + " chance of finishing the mission","Launch " + pas.TsFmt.FmtPct(A.LaunchSuccess) + ", arrival " + pas.TsFmt.FmtPct(A.InsertSuccess) + ", and " + pas.TsFmt.FmtPct(A.YearSurvival) + " survival for each year in space, multiplied together.","A more reliable rocket, more backups (risk class) or better radiation protection all raise the odds.",0);
    if ((A.Blockers === 0) && (A.Warnings === 0)) AddF(0,"CLOSED","The design closes",'Mass, power, data, money and time all balance with healthy margins. This is what engineers mean by a "closed" design.',"Fly it, or keep hunting for more science per dollar.",0);
    Result.$assign(A);
    return Result;
  };
  this.EncodeDesign = function (D) {
    var Result = "";
    var K = 0;
    var I = 0;
    var S = "";
    var Bits = "";
    S = "T1-" + pas.TsScenarios.Scenarios[D.Scenario].Id + "-" + pas.SysUtils.IntToStr(D.Difficulty) + "-";
    if (D.Sandbox) {
      S = S + "1-"}
     else S = S + "0-";
    S = S + pas.SysUtils.IntToStr(D.Orbit) + "-" + pas.SysUtils.IntToStr(D.Transfer) + "-";
    for (K = 0; K <= 11; K++) {
      if (K !== pas.TsTypes.TPartKind.pkBus) S = S + ".";
      S = S + pas.SysUtils.IntToStr(D.Part[K]);
    };
    Bits = "";
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if ((I <= (rtl.length(D.Instr) - 1)) && D.Instr[I]) {
        Bits = Bits + "1"}
       else Bits = Bits + "0";
    };
    S = S + "-" + pas.SysUtils.IntToStr(D.Launcher + 1) + "-" + Bits + "-" + pas.SysUtils.IntToStr(Math.round(D.SolarM2 * 10)) + "-" + pas.SysUtils.IntToStr(D.RtgCount) + "-" + pas.SysUtils.IntToStr(Math.round(D.BatteryWh)) + "-" + pas.SysUtils.IntToStr(Math.round(D.LifeYears * 100)) + "-" + pas.SysUtils.IntToStr(Math.round(D.ReservePct)) + "-" + pas.SysUtils.IntToStr(D.Seed);
    Result = S;
    return Result;
  };
  this.DecodeDesign = function (Code, D) {
    var Result = false;
    var P = [];
    var Q = [];
    var K = 0;
    var I = 0;
    var SI = 0;
    var V = 0;
    var Sc = pas.TsTypes.TScenario.$new();
    Result = false;
    P = $impl.SplitStr(pas.SysUtils.Trim(Code),"-");
    if ((rtl.length(P) !== 15) || (P[0] !== "T1")) return Result;
    SI = pas.TsScenarios.FindScenario(P[1]);
    if (SI < 0) return Result;
    Sc.$assign(pas.TsScenarios.Scenarios[SI]);
    V = pas.SysUtils.StrToIntDef(P[2],1);
    if ((V < 0) || (V > 2)) V = 1;
    D.$assign($mod.NewDesign(SI,V,P[3] === "1"));
    D.Orbit = pas.SysUtils.StrToIntDef(P[4],0);
    if ((D.Orbit < 0) || (D.Orbit > (rtl.length(Sc.Orbits) - 1))) D.Orbit = 0;
    D.Transfer = pas.SysUtils.StrToIntDef(P[5],0);
    if ((D.Transfer < 0) || (D.Transfer > (rtl.length(Sc.Transfers) - 1))) D.Transfer = 0;
    Q = $impl.SplitStr(P[6],".");
    I = 0;
    for (K = 0; K <= 11; K++) {
      if (I <= (rtl.length(Q) - 1)) {
        V = pas.SysUtils.StrToIntDef(Q[I],0);
        if ((V < 0) || (V > (rtl.length(pas.TsCatalog.Parts[K]) - 1))) V = 0;
        D.Part[K] = V;
      };
      I += 1;
    };
    D.Launcher = pas.SysUtils.StrToIntDef(P[7],0) - 1;
    if ((D.Launcher < -1) || (D.Launcher > (rtl.length(pas.TsCatalog.Launchers) - 1))) D.Launcher = -1;
    for (var $l = 0, $end = rtl.length(D.Instr) - 1; $l <= $end; $l++) {
      I = $l;
      D.Instr[I] = (I < P[8].length) && (P[8].charAt((I + 1) - 1) === "1");
    };
    D.SolarM2 = pas.TsTypes.Clamp(pas.SysUtils.StrToIntDef(P[9],20) / 10,0,200);
    D.RtgCount = pas.SysUtils.StrToIntDef(P[10],0);
    if ((D.RtgCount < 0) || (D.RtgCount > 5)) D.RtgCount = 0;
    D.BatteryWh = pas.TsTypes.Clamp(pas.SysUtils.StrToIntDef(P[11],300),0,20000);
    D.LifeYears = pas.TsTypes.Clamp(pas.SysUtils.StrToIntDef(P[12],200) / 100,0.25,10);
    D.ReservePct = pas.TsTypes.Clamp(pas.SysUtils.StrToIntDef(P[13],20),0,40);
    D.Seed = pas.SysUtils.StrToIntDef(P[14],12345);
    if (D.Seed < 1) D.Seed = 12345;
    Result = true;
    return Result;
  };
  $mod.$implcode = function () {
    $impl.SplitStr = function (S, Sep) {
      var Result = [];
      var I = 0;
      var Start = 0;
      Result = rtl.arraySetLength(Result,"",0);
      Start = 1;
      for (var $l = 1, $end = S.length; $l <= $end; $l++) {
        I = $l;
        if (S.charAt(I - 1) === Sep) {
          pas.TsTypes.AddStr({get: function () {
              return Result;
            }, set: function (v) {
              Result = v;
            }},pas.System.Copy(S,Start,I - Start));
          Start = I + 1;
        };
      };
      pas.TsTypes.AddStr({get: function () {
          return Result;
        }, set: function (v) {
          Result = v;
        }},pas.System.Copy(S,Start,(S.length - Start) + 1));
      return Result;
    };
  };
},["SysUtils","Math","TsCatalog","TsScenarios","TsFmt"]);
rtl.module("TsSim",["System","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.dkOverweight = 1;
  this.dkSupplier = 2;
  this.dkTestFail = 3;
  this.dkBudgetCut = 4;
  this.dkPartner = 5;
  this.dkStorm = 6;
  this.dkWheel = 7;
  this.dkStation = 8;
  this.dkDiscovery = 9;
  this.dkExtend = 10;
  this.dkEclipse = 11;
  this.dkMax = 11;
  this.TSimPhase = {"0": "spDevelopment", spDevelopment: 0, "1": "spLaunch", spLaunch: 1, "2": "spCruise", spCruise: 2, "3": "spArrival", spArrival: 3, "4": "spScience", spScience: 4, "5": "spDone", spDone: 5};
  this.TEventTone = {"0": "tnInfo", tnInfo: 0, "1": "tnGood", tnGood: 1, "2": "tnWarn", tnWarn: 2, "3": "tnBad", tnBad: 3, "4": "tnReal", tnReal: 4};
  rtl.recNewT(this,"TSimChoice",function () {
    this.Text = "";
    this.Hint = "";
    this.$eq = function (b) {
      return (this.Text === b.Text) && (this.Hint === b.Hint);
    };
    this.$assign = function (s) {
      this.Text = s.Text;
      this.Hint = s.Hint;
      return this;
    };
  });
  rtl.recNewT(this,"TSimEvent",function () {
    this.Week = 0;
    this.Phase = 0;
    this.Tone = 0;
    this.Title = "";
    this.Text = "";
    this.Source = "";
    this.Lesson = "";
    this.Decision = "";
    this.Outcome = "";
    this.Owner = 0;
    this.IsDecision = false;
    this.Kind = 0;
    this.Chosen = 0;
    this.$new = function () {
      var r = Object.create(this);
      r.Choices = [];
      return r;
    };
    this.$eq = function (b) {
      return (this.Week === b.Week) && (this.Phase === b.Phase) && (this.Tone === b.Tone) && (this.Title === b.Title) && (this.Text === b.Text) && (this.Source === b.Source) && (this.Lesson === b.Lesson) && (this.Decision === b.Decision) && (this.Outcome === b.Outcome) && (this.Owner === b.Owner) && (this.IsDecision === b.IsDecision) && (this.Kind === b.Kind) && (this.Chosen === b.Chosen) && (this.Choices === b.Choices);
    };
    this.$assign = function (s) {
      this.Week = s.Week;
      this.Phase = s.Phase;
      this.Tone = s.Tone;
      this.Title = s.Title;
      this.Text = s.Text;
      this.Source = s.Source;
      this.Lesson = s.Lesson;
      this.Decision = s.Decision;
      this.Outcome = s.Outcome;
      this.Owner = s.Owner;
      this.IsDecision = s.IsDecision;
      this.Kind = s.Kind;
      this.Chosen = s.Chosen;
      this.Choices = rtl.arrayRef(s.Choices);
      return this;
    };
  });
  rtl.recNewT(this,"TSimState",function () {
    this.Phase = 0;
    this.Week = 0;
    this.SciWeek = 0;
    this.PlanWeeks = 0;
    this.CruiseWeeks = 0;
    this.Rng = 0.0;
    this.Alive = false;
    this.LostAtLaunch = false;
    this.LostAtArrival = false;
    this.EndReason = "";
    this.EventCostM = 0.0;
    this.OpsCostM = 0.0;
    this.DelayYears = 0.0;
    this.LaunchYear = 0.0;
    this.Late = false;
    this.GrowthKg = 0.0;
    this.DryKg = 0.0;
    this.PropKg = 0.0;
    this.DvLeft = 0.0;
    this.DvStart = 0.0;
    this.SciQuality = 0.0;
    this.RateFactor = 0.0;
    this.SolarLoss = 0.0;
    this.FailMult = 0.0;
    this.PointTier = 0;
    this.SafeWeeks = 0;
    this.HalfLinkWeeks = 0;
    this.BlackoutWeeks = 0;
    this.SlowWeeks = 0;
    this.DustWeeks = 0;
    this.Dose = 0.0;
    this.DoseLimit = 0.0;
    this.DragLimitYears = 0.0;
    this.BatteryAged = false;
    this.StorageGbit = 0.0;
    this.PhaseDays = 0.0;
    this.BonusPct = 0.0;
    this.SciencePct = 0.0;
    this.GenGbit = 0.0;
    this.DownGbit = 0.0;
    this.LostGbit = 0.0;
    this.PowerSum = 0.0;
    this.SafeTotal = 0;
    this.Anomalies = 0;
    this.EventsSeen = 0;
    this.ExtendedWeeks = 0;
    this.InstrLost = 0;
    this.StormsRidden = 0;
    this.DragStorms = 0;
    this.FlareHits = 0;
    this.HasPending = false;
    this.DevLeft = 0;
    this.DevDone = false;
    this.EarthIdx = 0;
    this.ConjCycle = 0;
    this.DustDone = false;
    this.FlybyDone = false;
    this.HalfDone = false;
    this.$new = function () {
      var r = Object.create(this);
      r.D = pas.TsTypes.TDesign.$new();
      r.A = pas.TsTypes.TAnalysis.$new();
      r.InstrAlive = [];
      r.Cap = rtl.arraySetLength(null,0.0,9);
      r.Completion = rtl.arraySetLength(null,0.0,9);
      r.Realized = rtl.arraySetLength(null,0.0,9);
      r.HistScience = [];
      r.HistPower = [];
      r.HistData = [];
      r.HistStore = [];
      r.HistDv = [];
      r.Log = [];
      r.Pending = $mod.TSimEvent.$new();
      r.Used = rtl.arraySetLength(null,false,12);
      r.DecWeek = rtl.arraySetLength(null,0,12);
      return r;
    };
    this.$eq = function (b) {
      return this.D.$eq(b.D) && this.A.$eq(b.A) && (this.Phase === b.Phase) && (this.Week === b.Week) && (this.SciWeek === b.SciWeek) && (this.PlanWeeks === b.PlanWeeks) && (this.CruiseWeeks === b.CruiseWeeks) && (this.Rng === b.Rng) && (this.Alive === b.Alive) && (this.LostAtLaunch === b.LostAtLaunch) && (this.LostAtArrival === b.LostAtArrival) && (this.EndReason === b.EndReason) && (this.EventCostM === b.EventCostM) && (this.OpsCostM === b.OpsCostM) && (this.DelayYears === b.DelayYears) && (this.LaunchYear === b.LaunchYear) && (this.Late === b.Late) && (this.GrowthKg === b.GrowthKg) && (this.DryKg === b.DryKg) && (this.PropKg === b.PropKg) && (this.DvLeft === b.DvLeft) && (this.DvStart === b.DvStart) && (this.SciQuality === b.SciQuality) && (this.RateFactor === b.RateFactor) && (this.SolarLoss === b.SolarLoss) && (this.FailMult === b.FailMult) && (this.PointTier === b.PointTier) && (this.InstrAlive === b.InstrAlive) && rtl.arrayEq(this.Cap,b.Cap) && (this.SafeWeeks === b.SafeWeeks) && (this.HalfLinkWeeks === b.HalfLinkWeeks) && (this.BlackoutWeeks === b.BlackoutWeeks) && (this.SlowWeeks === b.SlowWeeks) && (this.DustWeeks === b.DustWeeks) && (this.Dose === b.Dose) && (this.DoseLimit === b.DoseLimit) && (this.DragLimitYears === b.DragLimitYears) && (this.BatteryAged === b.BatteryAged) && (this.StorageGbit === b.StorageGbit) && (this.PhaseDays === b.PhaseDays) && rtl.arrayEq(this.Completion,b.Completion) && rtl.arrayEq(this.Realized,b.Realized) && (this.BonusPct === b.BonusPct) && (this.SciencePct === b.SciencePct) && (this.GenGbit === b.GenGbit) && (this.DownGbit === b.DownGbit) && (this.LostGbit === b.LostGbit) && (this.PowerSum === b.PowerSum) && (this.SafeTotal === b.SafeTotal) && (this.Anomalies === b.Anomalies) && (this.EventsSeen === b.EventsSeen) && (this.ExtendedWeeks === b.ExtendedWeeks) && (this.InstrLost === b.InstrLost) && (this.StormsRidden === b.StormsRidden) && (this.DragStorms === b.DragStorms) && (this.FlareHits === b.FlareHits) && (this.HistScience === b.HistScience) && (this.HistPower === b.HistPower) && (this.HistData === b.HistData) && (this.HistStore === b.HistStore) && (this.HistDv === b.HistDv) && (this.Log === b.Log) && (this.HasPending === b.HasPending) && this.Pending.$eq(b.Pending) && rtl.arrayEq(this.Used,b.Used) && rtl.arrayEq(this.DecWeek,b.DecWeek) && (this.DevLeft === b.DevLeft) && (this.DevDone === b.DevDone) && (this.EarthIdx === b.EarthIdx) && (this.ConjCycle === b.ConjCycle) && (this.DustDone === b.DustDone) && (this.FlybyDone === b.FlybyDone) && (this.HalfDone === b.HalfDone);
    };
    this.$assign = function (s) {
      this.D.$assign(s.D);
      this.A.$assign(s.A);
      this.Phase = s.Phase;
      this.Week = s.Week;
      this.SciWeek = s.SciWeek;
      this.PlanWeeks = s.PlanWeeks;
      this.CruiseWeeks = s.CruiseWeeks;
      this.Rng = s.Rng;
      this.Alive = s.Alive;
      this.LostAtLaunch = s.LostAtLaunch;
      this.LostAtArrival = s.LostAtArrival;
      this.EndReason = s.EndReason;
      this.EventCostM = s.EventCostM;
      this.OpsCostM = s.OpsCostM;
      this.DelayYears = s.DelayYears;
      this.LaunchYear = s.LaunchYear;
      this.Late = s.Late;
      this.GrowthKg = s.GrowthKg;
      this.DryKg = s.DryKg;
      this.PropKg = s.PropKg;
      this.DvLeft = s.DvLeft;
      this.DvStart = s.DvStart;
      this.SciQuality = s.SciQuality;
      this.RateFactor = s.RateFactor;
      this.SolarLoss = s.SolarLoss;
      this.FailMult = s.FailMult;
      this.PointTier = s.PointTier;
      this.InstrAlive = rtl.arrayRef(s.InstrAlive);
      this.Cap = s.Cap.slice(0);
      this.SafeWeeks = s.SafeWeeks;
      this.HalfLinkWeeks = s.HalfLinkWeeks;
      this.BlackoutWeeks = s.BlackoutWeeks;
      this.SlowWeeks = s.SlowWeeks;
      this.DustWeeks = s.DustWeeks;
      this.Dose = s.Dose;
      this.DoseLimit = s.DoseLimit;
      this.DragLimitYears = s.DragLimitYears;
      this.BatteryAged = s.BatteryAged;
      this.StorageGbit = s.StorageGbit;
      this.PhaseDays = s.PhaseDays;
      this.Completion = s.Completion.slice(0);
      this.Realized = s.Realized.slice(0);
      this.BonusPct = s.BonusPct;
      this.SciencePct = s.SciencePct;
      this.GenGbit = s.GenGbit;
      this.DownGbit = s.DownGbit;
      this.LostGbit = s.LostGbit;
      this.PowerSum = s.PowerSum;
      this.SafeTotal = s.SafeTotal;
      this.Anomalies = s.Anomalies;
      this.EventsSeen = s.EventsSeen;
      this.ExtendedWeeks = s.ExtendedWeeks;
      this.InstrLost = s.InstrLost;
      this.StormsRidden = s.StormsRidden;
      this.DragStorms = s.DragStorms;
      this.FlareHits = s.FlareHits;
      this.HistScience = rtl.arrayRef(s.HistScience);
      this.HistPower = rtl.arrayRef(s.HistPower);
      this.HistData = rtl.arrayRef(s.HistData);
      this.HistStore = rtl.arrayRef(s.HistStore);
      this.HistDv = rtl.arrayRef(s.HistDv);
      this.Log = rtl.arrayRef(s.Log);
      this.HasPending = s.HasPending;
      this.Pending.$assign(s.Pending);
      this.Used = s.Used.slice(0);
      this.DecWeek = s.DecWeek.slice(0);
      this.DevLeft = s.DevLeft;
      this.DevDone = s.DevDone;
      this.EarthIdx = s.EarthIdx;
      this.ConjCycle = s.ConjCycle;
      this.DustDone = s.DustDone;
      this.FlybyDone = s.FlybyDone;
      this.HalfDone = s.HalfDone;
      return this;
    };
  });
  this.PhaseName = ["Development","Launch","Cruise","Arrival","Science operations","Mission complete"];
  this.SimStart = function (S, D) {
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var I = 0;
    var K = 0;
    var M = 0;
    Sc.$assign(pas.TsScenarios.Scenarios[D.Scenario]);
    O.$assign(Sc.Orbits[D.Orbit]);
    S.D.$assign(D);
    S.A.$assign(pas.TsEngine.Analyze(D));
    S.Phase = 0;
    S.Week = 0;
    S.SciWeek = 0;
    S.PlanWeeks = Math.round(D.LifeYears * 52);
    if (S.PlanWeeks < 4) S.PlanWeeks = 4;
    S.CruiseWeeks = Math.round(S.A.CruiseYears * 52);
    S.Rng = D.Seed;
    if (S.Rng < 1) S.Rng = 12345;
    S.Alive = true;
    S.LostAtLaunch = false;
    S.LostAtArrival = false;
    S.EndReason = "";
    S.EventCostM = 0;
    S.OpsCostM = 0;
    S.DelayYears = 0;
    S.LaunchYear = S.A.LaunchYear;
    S.Late = S.A.MissedDeadline;
    S.GrowthKg = 0;
    S.DryKg = S.A.DryKg;
    S.PropKg = S.A.PropKg;
    S.DvLeft = 0;
    S.DvStart = 0;
    S.SciQuality = 1;
    S.RateFactor = 1;
    S.SolarLoss = 0;
    S.FailMult = 1;
    S.PointTier = S.A.PointingTier;
    S.InstrAlive = rtl.arraySetLength(S.InstrAlive,false,rtl.length(pas.TsCatalog.Instruments));
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      S.InstrAlive[I] = (I <= (rtl.length(D.Instr) - 1)) && D.Instr[I] && pas.TsEngine.InstrumentOffered(D.Scenario,I);
    };
    $impl.RecomputeCap(S);
    S.SafeWeeks = 0;
    S.HalfLinkWeeks = 0;
    S.BlackoutWeeks = 0;
    S.SlowWeeks = 0;
    S.DustWeeks = 0;
    S.Dose = 0;
    S.BatteryAged = false;
    S.StorageGbit = 0;
    for (M = 0; M <= 8; M++) {
      S.Completion[M] = 0;
      S.Realized[M] = 0;
    };
    S.BonusPct = 0;
    S.SciencePct = 0;
    S.GenGbit = 0;
    S.DownGbit = 0;
    S.LostGbit = 0;
    S.PowerSum = 0;
    S.SafeTotal = 0;
    S.Anomalies = 0;
    S.EventsSeen = 0;
    S.ExtendedWeeks = 0;
    S.InstrLost = 0;
    S.StormsRidden = 0;
    S.DragStorms = 0;
    S.FlareHits = 0;
    S.HistScience = rtl.arraySetLength(S.HistScience,0.0,0);
    S.HistPower = rtl.arraySetLength(S.HistPower,0.0,0);
    S.HistData = rtl.arraySetLength(S.HistData,0.0,0);
    S.HistStore = rtl.arraySetLength(S.HistStore,0.0,0);
    S.HistDv = rtl.arraySetLength(S.HistDv,0.0,0);
    S.Log = rtl.arraySetLength(S.Log,$mod.TSimEvent,0);
    S.HasPending = false;
    for (K = 0; K <= 11; K++) {
      S.Used[K] = false;
      S.DecWeek[K] = -1;
    };
    var $tmp = D.Difficulty;
    if ($tmp === 0) {
      S.DevLeft = 1}
     else if ($tmp === 2) {
      S.DevLeft = 3}
     else {
      S.DevLeft = 2;
    };
    S.DevDone = false;
    S.EarthIdx = 0;
    S.ConjCycle = -1000;
    S.DustDone = false;
    S.FlybyDone = false;
    S.HalfDone = false;
    S.DoseLimit = 0.85 + (0.3 * $impl.Rnd(S));
    S.DragLimitYears = 0;
    if ((O.DragLifeYears > 0) && (pas.TsCatalog.Parts[1][D.Part[1]].Tier === 0)) S.DragLimitYears = O.DragLifeYears * (0.9 + (0.2 * $impl.Rnd(S)));
    S.PhaseDays = $impl.Rnd(S) * 400;
    S.DecWeek[6] = Math.round(S.PlanWeeks * (0.12 + (0.10 * $impl.Rnd(S))));
    S.DecWeek[7] = Math.round(S.PlanWeeks * (0.32 + (0.10 * $impl.Rnd(S))));
    S.DecWeek[8] = Math.round(S.PlanWeeks * (0.50 + (0.08 * $impl.Rnd(S))));
    S.DecWeek[9] = Math.round(S.PlanWeeks * (0.64 + (0.10 * $impl.Rnd(S))));
    S.DecWeek[11] = Math.round(S.PlanWeeks * (0.40 + (0.05 * $impl.Rnd(S))));
    if (D.Difficulty === 0) {
      S.DecWeek[7] = -1;
      S.DecWeek[8] = -1;
    };
    $impl.LogEvent(S,0,"Mission confirmed","The review board has approved the design. Planned cost " + pas.TsFmt.FmtMoney(S.A.CostTotal) + " including " + pas.TsFmt.FmtMoney(S.A.CostReserve) + " of reserves. Development should take " + pas.TsFmt.FmtYears(S.A.DevYears) + ".","","",0);
  };
  this.SimAdvance = function (S) {
    if (S.HasPending || (S.Phase === 5)) return;
    var $tmp = S.Phase;
    if ($tmp === 0) {
      $impl.DevTick(S)}
     else if ($tmp === 1) {
      $impl.LaunchTick(S)}
     else if ($tmp === 2) {
      $impl.CruiseTick(S)}
     else if ($tmp === 3) {
      $impl.ArrivalTick(S)}
     else if ($tmp === 4) $impl.ScienceTick(S);
  };
  this.SimChoose = function (S, Choice) {
    var E = $mod.TSimEvent.$new();
    var Dev = 0.0;
    var Cost = 0.0;
    var P = 0.0;
    var N = 0;
    var I = 0;
    var H = 0;
    var Kg = 0;
    var Ext = 0;
    var Adcs = pas.TsTypes.TPart.$new();
    if (!S.HasPending) return;
    E.$assign(S.Pending);
    if ((Choice < 0) || (Choice > (rtl.length(E.Choices) - 1))) Choice = 0;
    E.Chosen = Choice;
    E.Decision = E.Choices[Choice].Text;
    E.Tone = 0;
    Dev = S.A.DevCostM;
    Adcs.$assign(pas.TsCatalog.Parts[2][S.D.Part[2]]);
    var $tmp = E.Kind;
    if ($tmp === 1) {
      H = $impl.HeaviestAlive(S);
      Kg = 1;
      if (H >= 0) Kg = Math.round(pas.TsTypes.MaxD(1,pas.TsCatalog.Instruments[H].MassKg * 0.12));
      if (Choice === 0) {
        Cost = pas.TsTypes.MaxD(0.5,0.03 * Dev);
        $impl.Spend(S,Cost);
        E.Outcome = "The redesign cost " + pas.TsFmt.FmtMoney(Cost) + " and the mass is back on target.";
      } else if (Choice === 1) {
        S.GrowthKg = S.GrowthKg + (2 * Kg);
        E.Outcome = "The spacecraft is " + pas.SysUtils.IntToStr(2 * Kg) + " kg heavier. Your margin will have to absorb it.";
      } else {
        S.SciQuality = S.SciQuality * 0.93;
        E.Outcome = "The instrument flies with fewer modes. Science quality is down about 7 %.";
      };
    } else if ($tmp === 2) {
      if (Choice === 0) {
        S.DelayYears = S.DelayYears + 0.4;
        E.Outcome = "Development is five months longer.";
      } else if (Choice === 1) {
        Cost = pas.TsTypes.MaxD(0.5,0.035 * Dev);
        $impl.Spend(S,Cost);
        E.Outcome = "The rushed part arrived on time for " + pas.TsFmt.FmtMoney(Cost) + ".";
      } else {
        S.FailMult = S.FailMult * 1.3;
        E.Outcome = "The schedule held, but the spacecraft will fly with less testing behind it.";
      }}
     else if ($tmp === 3) {
      if (Choice === 0) {
        Cost = pas.TsTypes.MaxD(0.3,0.025 * Dev);
        $impl.Spend(S,Cost);
        S.DelayYears = S.DelayYears + 0.15;
        E.Outcome = "The new hinge passed the test. Cost " + pas.TsFmt.FmtMoney(Cost) + " and two months.";
      } else {
        Cost = pas.TsTypes.MaxD(0.1,0.006 * Dev);
        $impl.Spend(S,Cost);
        S.FailMult = S.FailMult * 1.2;
        E.Outcome = "The patch held on the table. Whether it holds in flight is another matter.";
      }}
     else if ($tmp === 4) {
      if (Choice === 0) {
        Cost = pas.TsTypes.MaxD(0.5,0.04 * Dev);
        $impl.Spend(S,Cost);
        E.Outcome = "Reserves covered the " + pas.TsFmt.FmtMoney(Cost) + " gap.";
      } else if (Choice === 1) {
        S.PlanWeeks = Math.round(S.PlanWeeks * 0.75);
        if (S.PlanWeeks < 4) S.PlanWeeks = 4;
        E.Outcome = "The planned mission is now " + pas.TsFmt.FmtYears(S.PlanWeeks / 52) + ".";
      } else {
        S.DelayYears = S.DelayYears + 0.5;
        E.Outcome = "Work slows down. Launch readiness slips six months.";
      }}
     else if ($tmp === 5) {
      if (Choice === 0) {
        S.RateFactor = S.RateFactor * 1.25;
        E.Tone = 1;
        E.Outcome = "The partner's stations will add a quarter more downlink.";
      } else E.Outcome = "You keep full control of the data and the ground plan stays as it was."}
     else if ($tmp === 6) {
      if (Choice === 0) {
        S.SafeWeeks = S.SafeWeeks + 1;
        E.Outcome = "The spacecraft waited out the storm with its instruments off and came back unharmed.";
      } else {
        P = 0.12 + (0.2 * S.A.RadExposure);
        if (S.D.Difficulty === 0) {
          P = P - 0.05}
         else if (S.D.Difficulty === 2) P = P + 0.08;
        if ($impl.Rnd(S) < P) {
          E.Tone = 3;
          I = $impl.RandomAlive(S);
          if ((I >= 0) && ($impl.AliveCount(S) > 1)) {
            S.InstrAlive[I] = false;
            S.InstrLost += 1;
            $impl.RecomputeCap(S);
            E.Outcome = "The storm hit hard. The " + pas.TsCatalog.Instruments[I].Name + " was damaged beyond recovery.";
          } else {
            S.SolarLoss = S.SolarLoss + 0.08;
            E.Outcome = "The storm hit hard. The solar panels lost 8 % of their output for good.";
          };
        } else {
          E.Tone = 1;
          if (S.Cap[7] > 20) {
            S.BonusPct = S.BonusPct + 3;
            E.Outcome = "The spacecraft came through, and your fields and particles instruments recorded the whole storm. A rare data set.";
          } else {
            S.BonusPct = S.BonusPct + 1;
            E.Outcome = "The spacecraft came through unharmed and lost no observing time.";
          };
        };
      }}
     else if ($tmp === 7) {
      if (Choice === 0) {
        S.SlowWeeks = S.SlowWeeks + 8;
        E.Outcome = "The wheel cooled down and recovered. Operations run gently for two months.";
      } else if ($impl.Rnd(S) < 0.4) {
        if (Math.round(Adcs.B) === 1) {
          E.Tone = 1;
          E.Outcome = "The wheel seized, but the spare you paid for took over. Pointing is unaffected.";
        } else {
          E.Tone = 3;
          S.PointTier = 0;
          S.RateFactor = S.RateFactor * 0.7;
          $impl.RecomputeCap(S);
          E.Outcome = "The wheel seized. With two wheels left the spacecraft can no longer hold steady.";
        };
      } else {
        E.Tone = 1;
        E.Outcome = "The friction settled by itself. No science was lost.";
      }}
     else if ($tmp === 8) {
      if (Choice === 0) {
        Cost = pas.TsTypes.MaxD(0.6,0.012 * Dev);
        $impl.Spend(S,Cost);
        E.Outcome = "Another network filled in for " + pas.TsFmt.FmtMoney(Cost) + ".";
      } else {
        S.HalfLinkWeeks = S.HalfLinkWeeks + 6;
        E.Outcome = "Six weeks at half the downlink. The recorder has to hold the backlog.";
      }}
     else if ($tmp === 9) {
      if (Choice === 0) {
        S.SlowWeeks = S.SlowWeeks + 2;
        if (S.DvLeft > 0) S.DvLeft = S.DvLeft * 0.97;
        if ($impl.Rnd(S) < 0.75) {
          P = 4 + (4 * $impl.Rnd(S));
          S.BonusPct = S.BonusPct + P;
          E.Tone = 1;
          E.Outcome = "It was real. The follow-up observations are a highlight of the mission (+" + pas.TsFmt.FmtNum(P,0) + " science points).";
        } else E.Outcome = "The follow-up found nothing unusual. Two weeks and a little propellant spent on a false alarm.";
      } else E.Outcome = "The plan carries on unchanged. Someone else may follow it up one day."}
     else if ($tmp === 10) {
      if (Choice === 0) {
        Ext = rtl.trunc(S.PlanWeeks / 2);
        if (Ext < 13) Ext = 13;
        S.PlanWeeks = S.PlanWeeks + Ext;
        S.ExtendedWeeks = Ext;
        E.Tone = 1;
        E.Outcome = "The mission is extended by " + pas.TsFmt.FmtYears(Ext / 52) + ".";
      } else E.Outcome = "The mission ends on schedule."}
     else if ($tmp === 11) if (Choice === 0) {
      S.SafeWeeks = S.SafeWeeks + 1;
      E.Outcome = "Everything non-essential was switched off. The spacecraft woke up cold but healthy.";
    } else if ($impl.Rnd(S) < 0.5) {
      E.Tone = 3;
      S.SolarLoss = S.SolarLoss + 0.15;
      E.Outcome = "The battery ran flat and was damaged. The power system has lost about 15 % for good.";
    } else {
      E.Tone = 1;
      E.Outcome = "The battery just held. No science was lost.";
    };
    N = rtl.length(S.Log);
    S.Log = rtl.arraySetLength(S.Log,$mod.TSimEvent,N + 1);
    S.Log[N].$assign(E);
    S.HasPending = false;
    if ((E.Kind === 10) && (Choice !== 0)) {
      $impl.LogEvent(S,1,"Mission complete","Operations ended as planned after " + pas.TsFmt.FmtYears(S.SciWeek / 52) + " of science.","","",0);
      $impl.EndMission(S,"Completed");
    };
  };
  this.SimProgress = function (S) {
    var Result = 0.0;
    var Total = 0.0;
    Total = S.CruiseWeeks + S.PlanWeeks;
    if (S.Phase === 5) {
      Result = 1}
     else if ((S.Phase === 0) || (S.Phase === 1) || (Total <= 0)) {
      Result = 0}
     else Result = pas.TsTypes.Clamp(S.Week / Total,0,1);
    return Result;
  };
  this.SimFinalCost = function (S) {
    var Result = 0.0;
    Result = S.A.DevCostM + S.A.CostLaunch + S.A.SlipCostM + S.OpsCostM + S.EventCostM;
    return Result;
  };
  this.SimMissionYear = function (S) {
    var Result = 0.0;
    Result = S.LaunchYear + (S.Week / 52);
    return Result;
  };
  $mod.$implcode = function () {
    $impl.Rnd = function (S) {
      var Result = 0.0;
      var Q = 0;
      S.Rng = S.Rng * 16807.0;
      Q = pas.System.Trunc(S.Rng / 2147483647.0);
      S.Rng = S.Rng - (2147483647.0 * Q);
      if (S.Rng < 1) S.Rng = 1;
      Result = S.Rng / 2147483647.0;
      return Result;
    };
    $impl.LogEvent = function (S, ATone, ATitle, AText, ASource, ALesson, AOwner) {
      var N = 0;
      N = rtl.length(S.Log);
      S.Log = rtl.arraySetLength(S.Log,$mod.TSimEvent,N + 1);
      S.Log[N].Week = S.Week;
      S.Log[N].Phase = S.Phase;
      S.Log[N].Tone = ATone;
      S.Log[N].Title = ATitle;
      S.Log[N].Text = AText;
      S.Log[N].Source = ASource;
      S.Log[N].Lesson = ALesson;
      S.Log[N].Decision = "";
      S.Log[N].Outcome = "";
      S.Log[N].Owner = AOwner;
      S.Log[N].IsDecision = false;
      S.Log[N].Kind = 0;
      S.Log[N].Chosen = -1;
      S.Log[N].Choices = rtl.arraySetLength(S.Log[N].Choices,$mod.TSimChoice,0);
    };
    $impl.Ask = function (S, AKind, ATitle, AText, ASource, ALesson, AOwner) {
      S.Pending.Week = S.Week;
      S.Pending.Phase = S.Phase;
      S.Pending.Tone = 2;
      S.Pending.Title = ATitle;
      S.Pending.Text = AText;
      S.Pending.Source = ASource;
      S.Pending.Lesson = ALesson;
      S.Pending.Decision = "";
      S.Pending.Outcome = "";
      S.Pending.Owner = AOwner;
      S.Pending.IsDecision = true;
      S.Pending.Kind = AKind;
      S.Pending.Chosen = -1;
      S.Pending.Choices = rtl.arraySetLength(S.Pending.Choices,$mod.TSimChoice,0);
      S.HasPending = true;
      S.Used[AKind] = true;
    };
    $impl.Opt = function (S, AText, AHint) {
      var N = 0;
      N = rtl.length(S.Pending.Choices);
      S.Pending.Choices = rtl.arraySetLength(S.Pending.Choices,$mod.TSimChoice,N + 1);
      S.Pending.Choices[N].Text = AText;
      S.Pending.Choices[N].Hint = AHint;
    };
    $impl.AliveCount = function (S) {
      var Result = 0;
      var I = 0;
      Result = 0;
      for (var $l = 0, $end = rtl.length(S.InstrAlive) - 1; $l <= $end; $l++) {
        I = $l;
        if (S.InstrAlive[I]) Result += 1;
      };
      return Result;
    };
    $impl.HeaviestAlive = function (S) {
      var Result = 0;
      var I = 0;
      Result = -1;
      for (var $l = 0, $end = rtl.length(S.InstrAlive) - 1; $l <= $end; $l++) {
        I = $l;
        if (S.InstrAlive[I] && ((Result < 0) || (pas.TsCatalog.Instruments[I].MassKg > pas.TsCatalog.Instruments[Result].MassKg))) Result = I;
      };
      return Result;
    };
    $impl.RandomAlive = function (S) {
      var Result = 0;
      var I = 0;
      var N = 0;
      var Pick = 0;
      Result = -1;
      N = $impl.AliveCount(S);
      if (N === 0) return Result;
      Pick = pas.System.Trunc($impl.Rnd(S) * N);
      if (Pick >= N) Pick = N - 1;
      for (var $l = 0, $end = rtl.length(S.InstrAlive) - 1; $l <= $end; $l++) {
        I = $l;
        if (S.InstrAlive[I]) {
          if (Pick === 0) {
            Result = I;
            return Result;
          };
          Pick -= 1;
        };
      };
      return Result;
    };
    $impl.RecomputeCap = function (S) {
      var Q = [];
      pas.TsEngine.InstrumentQuality(S.D,S.InstrAlive,S.PointTier,{get: function () {
          return Q;
        }, set: function (v) {
          Q = v;
        }});
      S.Cap = pas.TsEngine.MeasureCapability(S.D,Q);
    };
    $impl.ScienceNow = function (S) {
      var Result = 0.0;
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      var M = 0;
      var Sum = 0.0;
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      O.$assign(Sc.Orbits[S.D.Orbit]);
      Sum = 0;
      for (M = 0; M <= 8; M++) Sum = Sum + (Sc.Weight[M] * S.Realized[M]);
      Result = (100 * Sum * O.Coverage) / Sc.FullScience;
      if (S.Late && Sc.ArriveBy) Result = Result * Sc.LateFactor;
      Result = Result + S.BonusPct;
      return Result;
    };
    $impl.Spend = function (S, Amount) {
      S.EventCostM = S.EventCostM + Amount;
    };
    $impl.EndMission = function (S, AReason) {
      S.EndReason = AReason;
      S.Phase = 5;
    };
    $impl.AskDev = function (S) {
      var Kind = 0;
      var Tries = 0;
      var H = 0;
      var Kg = 0;
      var Dev = 0.0;
      var Part = "";
      Dev = S.A.DevCostM;
      Kind = 0;
      Tries = 0;
      do {
        Kind = 1 + pas.System.Trunc($impl.Rnd(S) * 5);
        if (Kind > 5) Kind = 5;
        Tries += 1;
      } while (!(!S.Used[Kind] || (Tries > 30)));
      if (S.Used[Kind]) return;
      var $tmp = Kind;
      if ($tmp === 1) {
        H = $impl.HeaviestAlive(S);
        if (H < 0) {
          S.Used[Kind] = true;
          return;
        };
        Kg = Math.round(pas.TsTypes.MaxD(1,pas.TsCatalog.Instruments[H].MassKg * 0.12));
        $impl.Ask(S,Kind,"An instrument came in overweight","The " + pas.TsCatalog.Instruments[H].Name + " team has delivered their flight unit. It is " + pas.SysUtils.IntToStr(Kg) + " kg heavier than promised.","","Mass growth is so common that NASA teams hold back 25 to 30 % at the start. " + "Margin is not waste. It is what you spend when reality arrives.",2);
        $impl.Opt(S,"Pay for a lighter redesign","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.5,0.03 * Dev)) + ". No extra mass.");
        $impl.Opt(S,"Accept the extra mass","+" + pas.SysUtils.IntToStr(2 * Kg) + " kg with stronger brackets. Eats launch margin and fuel reserve.");
        $impl.Opt(S,"Strip features from the instrument","No cost and no mass, but about 7 % less science.");
      } else if ($tmp === 2) {
        var $tmp1 = pas.System.Trunc($impl.Rnd(S) * 3);
        if ($tmp1 === 0) {
          Part = "reaction wheels"}
         else if ($tmp1 === 1) {
          Part = "flight computer"}
         else {
          Part = "star tracker";
        };
        $impl.Ask(S,Kind,"A key part is late","The supplier of your " + Part + " has a production problem. Delivery will be five months late.","","Space hardware comes from a handful of specialist suppliers. One late part can hold up a whole spacecraft.",0);
        $impl.Opt(S,"Wait for it","Five months of delay. If that misses a launch window, you wait for the next one.");
        $impl.Opt(S,"Pay a second supplier to rush one","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.5,0.035 * Dev)) + ". No delay.");
        $impl.Opt(S,"Skip some testing to catch up","No cost and no delay, but faults in flight become 30 % more likely.");
      } else if ($tmp === 3) {
        $impl.Ask(S,Kind,"Shake test failure","On the vibration table that mimics a rocket launch, a solar panel hinge cracked.","","Finding a weakness on the ground is a success. Hubble's flawed mirror slipped through because " + "one complete end-to-end test was skipped, and fixing it took a Shuttle mission.",2);
        $impl.Opt(S,"Redesign the hinge and test again","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.3,0.025 * Dev)) + " and two months.");
        $impl.Opt(S,"Reinforce it and move on","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.1,0.006 * Dev)) + ". Faults in flight become 20 % more likely.");
      } else if ($tmp === 4) {
        $impl.Ask(S,Kind,"This year's funding is cut","The agency's budget came in lower than planned. Your project must find " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.5,0.04 * Dev)) + " this year.","","Missions are funded one year at a time. Stretching a project to save money now nearly always costs more in total.",0);
        $impl.Opt(S,"Cover it from reserves","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.5,0.04 * Dev)) + ". Nothing else changes.");
        $impl.Opt(S,"Promise a shorter mission","Planned science operations shrink by a quarter.");
        $impl.Opt(S,"Slow down and stretch the schedule","Six months of delay, and salaries to pay while you wait.");
      } else {
        $impl.Ask(S,5,"A partner agency offers help","Another space agency offers time on its ground stations in exchange for a share of the data.","","Almost every modern mission is international. NISAR is half Indian, Chandrayaan-1 carried NASA " + "instruments and Canada built the laser altimeter on OSIRIS-REx.",0);
        $impl.Opt(S,"Accept and share the data","A quarter more data-link capacity for the whole mission.");
        $impl.Opt(S,"Decline and keep it simple","Nothing changes.");
      };
    };
    $impl.FinishDevelopment = function (S) {
      var Sc = pas.TsTypes.TScenario.$new();
      var Prop = pas.TsTypes.TPart.$new();
      var G = 0.0;
      var Wet = 0.0;
      var Over = 0.0;
      var Ready = 0.0;
      var Launch = 0.0;
      var Wait = 0.0;
      var H = 0;
      var K = 0;
      var WasLate = false;
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      Prop.$assign(pas.TsCatalog.Parts[1][S.D.Part[1]]);
      var $tmp = S.D.Difficulty;
      if ($tmp === 0) {
        G = 0.02 + (0.03 * $impl.Rnd(S))}
       else if ($tmp === 2) {
        G = 0.07 + (0.11 * $impl.Rnd(S))}
       else {
        G = 0.04 + (0.09 * $impl.Rnd(S));
      };
      S.GrowthKg = S.GrowthKg + (S.A.DryKg * G);
      S.DryKg = S.A.DryKg + S.GrowthKg;
      S.PropKg = S.A.PropKg;
      if (S.A.DryKg > 0) S.PropKg = (S.A.PropKg * S.DryKg) / S.A.DryKg;
      Wet = S.DryKg + S.PropKg;
      if ((S.A.LvCapKg > 0) && (Wet > S.A.LvCapKg)) {
        Over = Wet - S.A.LvCapKg;
        if (Over > (S.PropKg * 0.6)) {
          H = $impl.HeaviestAlive(S);
          if ((H >= 0) && ($impl.AliveCount(S) > 1)) {
            S.InstrAlive[H] = false;
            S.InstrLost += 1;
            S.DryKg = S.DryKg - pas.TsCatalog.Instruments[H].MassKg;
            $impl.RecomputeCap(S);
            $impl.LogEvent(S,3,"Instrument removed to save mass","The spacecraft grew " + pas.TsFmt.FmtMass(S.GrowthKg) + " heavier during development and no longer fits the rocket. " + "The " + pas.TsCatalog.Instruments[H].Name + " was taken off before launch.","","With too little mass margin, growth has to be paid for in science.",2);
          };
          Wet = S.DryKg + S.PropKg;
          Over = Wet - S.A.LvCapKg;
        };
        if (Over > 0) {
          if (Over > S.PropKg) Over = S.PropKg;
          S.PropKg = S.PropKg - Over;
          $impl.LogEvent(S,2,"Overweight at the launch site","The spacecraft grew " + pas.TsFmt.FmtMass(S.GrowthKg) + " heavier during development and went over the rocket's limit. " + "Engineers drained " + pas.TsFmt.FmtMass(Over) + " of propellant to make it fit.","","That propellant was your safety margin and part of your mission life.",2);
        };
      } else if (S.A.LvCapKg > 0) $impl.LogEvent(S,0,"Mass grew by " + pas.TsFmt.FmtMass(S.GrowthKg),"As nearly always happens, the spacecraft gained weight while it was built (" + pas.TsFmt.FmtPct(G) + "), and needed " + pas.TsFmt.FmtMass(S.PropKg - S.A.PropKg) + " more propellant to match. Your launch margin of " + pas.TsFmt.FmtPct(S.A.MassMargin) + " absorbed both.","","",2);
      S.DvLeft = 0;
      if ((Prop.Tier > 0) && (S.PropKg > 0) && (S.DryKg > 0)) S.DvLeft = Prop.A * 9.80665 * Math.log((S.DryKg + S.PropKg) / S.DryKg);
      S.DvStart = S.DvLeft;
      WasLate = S.Late;
      Ready = S.A.DevYears + S.DelayYears;
      Launch = Ready;
      if (Sc.WindowYears > 0) {
        Launch = Sc.WindowYears;
        K = 0;
        while ((Launch < (Ready - 0.001)) && (K < 20)) {
          Launch = Launch + Sc.WindowPeriod;
          K += 1;
        };
      };
      if (Launch < S.A.LaunchYear) Launch = S.A.LaunchYear;
      Wait = Launch - S.A.LaunchYear;
      S.LaunchYear = Launch;
      if (Wait > 0.01) {
        $impl.Spend(S,Wait * 0.08 * S.A.DevCostM);
        if ((Sc.WindowYears > 0) && (Wait > 1)) {
          $impl.LogEvent(S,3,"Launch window missed","The delays pushed the spacecraft past its launch window. The planets will not line up again for " + pas.TsFmt.FmtYears(Sc.WindowPeriod) + ". The team is paid to wait: " + pas.TsFmt.FmtMoney(Wait * 0.08 * S.A.DevCostM) + ".","","A small slip can turn into a two-year wait when the destination is another planet.",0)}
         else $impl.LogEvent(S,2,"Launch delayed by " + pas.TsFmt.FmtYears(Wait),"Keeping the team together while waiting cost " + pas.TsFmt.FmtMoney(Wait * 0.08 * S.A.DevCostM) + ".","","",0);
      };
      if (Sc.ArriveBy) {
        S.Late = (Launch + S.A.CruiseYears) > (Sc.DeadlineYears + 0.001)}
       else S.Late = Launch > (Sc.DeadlineYears + 0.001);
      if (S.Late && !WasLate) $impl.LogEvent(S,2,"The deadline has been missed","After the delays, the mission can no longer meet its deadline.","","",0);
      S.DevDone = true;
      S.Phase = 1;
    };
    $impl.DevTick = function (S) {
      if (S.DevLeft > 0) {
        S.DevLeft -= 1;
        $impl.AskDev(S);
        if (S.HasPending) return;
      };
      if (S.DevLeft <= 0) $impl.FinishDevelopment(S);
    };
    $impl.LaunchTick = function (S) {
      var Sc = pas.TsTypes.TScenario.$new();
      var L = pas.TsTypes.TLauncher.$new();
      var Name = "";
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      Name = "The rocket";
      if (S.D.Launcher >= 0) {
        L.$assign(pas.TsCatalog.Launchers[S.D.Launcher]);
        Name = L.Name;
        if (L.Rideshare && ($impl.Rnd(S) < 0.3)) {
          S.LaunchYear = S.LaunchYear + 0.5;
          $impl.Spend(S,0.5 * 0.08 * S.A.DevCostM);
          $impl.LogEvent(S,2,"Your ride slipped six months","The main passenger on your shared rocket was not ready, so you waited too. Cost: " + pas.TsFmt.FmtMoney(0.5 * 0.08 * S.A.DevCostM) + ".","","NASA's Janus asteroid mission was built and ready, then lost its trajectory when the mission it was sharing a rocket with slipped a year.",0);
          if (Sc.ArriveBy && ((S.LaunchYear + S.A.CruiseYears) > (Sc.DeadlineYears + 0.001))) S.Late = true;
        };
      };
      if ($impl.Rnd(S) < S.A.LaunchSuccess) {
        $impl.LogEvent(S,1,"Liftoff",Name + " delivered the spacecraft to " + pas.TsEngine.LaunchTargetName(S.D) + ". Launch mass " + pas.TsFmt.FmtMass(S.DryKg + S.PropKg) + ".","","",0);
        if (S.CruiseWeeks > 0) {
          S.Phase = 2}
         else S.Phase = 3;
      } else {
        S.LostAtLaunch = true;
        S.Alive = false;
        $impl.LogEvent(S,3,"Launch failure",Name + " failed during ascent and the spacecraft was lost. This rocket succeeds about " + pas.TsFmt.FmtPct(S.A.LaunchSuccess) + " of the time.","","Every rocket has a track record. NASA will only fly its most valuable spacecraft on rockets with a long one.",0);
        $impl.EndMission(S,"Lost in a launch failure");
      };
    };
    $impl.SpaceWeatherTick = function (S, WeekSpan, InScience) {
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      var I = 0;
      var D0 = 0;
      var Wk = 0;
      var Cur = 0;
      var W = pas.TsTypes.TSpaceWeather.$new();
      var Logged = false;
      if (rtl.length(pas.TsScenarios.SpaceWeather) === 0) return;
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      O.$assign(Sc.Orbits[S.D.Orbit]);
      D0 = pas.TsFmt.DayNumber(pas.TsScenarios.SpaceWeather[0].Date);
      Logged = false;
      Cur = S.Week % 52;
      for (var $l = 0, $end = rtl.length(pas.TsScenarios.SpaceWeather) - 1; $l <= $end; $l++) {
        I = $l;
        W.$assign(pas.TsScenarios.SpaceWeather[I]);
        Wk = ((rtl.trunc((pas.TsFmt.DayNumber(W.Date) - D0) / 7) % 52) + 52) % 52;
        if ((Wk < Cur) || (Wk >= (Cur + WeekSpan))) continue;
        if (W.Kind === "SEP") {
          if (Sc.NearEarth && (O.RadLevel === 0)) continue;
          if (S.A.RadExposure >= 1) {
            S.SolarLoss = S.SolarLoss + 0.01;
            if ($impl.Rnd(S) < 0.45) {
              if (InScience) S.SafeWeeks = S.SafeWeeks + 1;
              if (!Logged) $impl.LogEvent(S,4,"Particle storm upset the computer","A burst of high-energy particles from the Sun scrambled the unprotected flight computer. " + "The spacecraft dropped into safe mode and lost a week.","Real event: " + pas.TsScenarios.WeatherLabel(W) + " (" + pas.TsScenarios.SpaceWeatherSource + ")","Radiation-hardened electronics and shielding exist for exactly this.",2);
              Logged = true;
            };
          } else {
            S.SolarLoss = S.SolarLoss + 0.004;
            S.StormsRidden += 1;
            if (!Logged && (S.StormsRidden === 1)) {
              $impl.LogEvent(S,4,"Rode out a particle storm","A burst of high-energy particles from the Sun swept over the spacecraft. The protected electronics carried on, " + "though the solar panels lost a little output for good.","Real event: " + pas.TsScenarios.WeatherLabel(W) + " (" + pas.TsScenarios.SpaceWeatherSource + ")","",2);
              Logged = true;
            };
          };
        } else if ((W.Kind === "GST") && Sc.NearEarth && (O.AltKm < 1000) && (W.Strength >= 0.6)) {
          if (S.DvLeft > 2) {
            S.DvLeft = S.DvLeft - (2 * W.Strength)}
           else if (S.DragLimitYears > 0) S.DragLimitYears = S.DragLimitYears - 0.04;
          S.DragStorms += 1;
          if (!Logged && (S.DragStorms === 1)) {
            $impl.LogEvent(S,4,"Geomagnetic storm raised the drag","A storm in Earth's magnetic field heated the upper atmosphere, which swelled upward. " + "Drag on your low-flying satellite jumped for several days.","Real event: " + pas.TsScenarios.WeatherLabel(W) + " (" + pas.TsScenarios.SpaceWeatherSource + ")","In February 2022 a storm like this brought down 38 newly launched Starlink satellites.",3);
            Logged = true;
          };
        } else if ((W.Kind === "FLR") && (W.Strength >= 0.5) && InScience) {
          S.FlareHits += 1;
          if (!Logged && (S.FlareHits === 1)) {
            $impl.LogEvent(S,4,"Solar flare disturbed the radio link","An X-class flare bathed Earth's daylit side in X-rays and garbled a ground-station pass.","Real event: " + pas.TsScenarios.WeatherLabel(W) + " (" + pas.TsScenarios.SpaceWeatherSource + ")","",3);
            Logged = true;
          };
        };
      };
    };
    $impl.CruiseTick = function (S) {
      var Step = 0;
      var PFatal = 0.0;
      Step = 4;
      if ((S.Week + Step) > S.CruiseWeeks) Step = S.CruiseWeeks - S.Week;
      if (Step < 1) Step = 1;
      $impl.SpaceWeatherTick(S,Step,false);
      S.Week = S.Week + Step;
      S.OpsCostM = S.OpsCostM + ((0.5 * S.A.OpsPerYearM * Step) / 52);
      PFatal = 1 - Math.exp((-S.A.AnomalyRate * S.FailMult * S.A.FatalShare * 0.5 * Step) / 52);
      if ((S.D.Difficulty !== 0) && ($impl.Rnd(S) < PFatal)) {
        S.Alive = false;
        S.Anomalies += 1;
        $impl.LogEvent(S,3,"Contact lost during cruise","The spacecraft stopped answering " + pas.TsFmt.FmtYears(S.Week / 52) + " after launch and never recovered.","","Mars Observer fell silent three days before reaching Mars in 1993. Backups and testing are what you pay for to make this less likely.",2);
        $impl.EndMission(S,"Lost during the cruise");
        return;
      };
      if (!S.HalfDone && (S.CruiseWeeks >= 16) && (S.Week >= rtl.trunc(S.CruiseWeeks / 2))) {
        S.HalfDone = true;
        $impl.LogEvent(S,0,"Halfway there","All systems normal. A radio signal now takes " + pas.TsFmt.FmtNum(S.A.LightDelayMin * 0.6,1) + " minutes to reach the spacecraft, so it has to look after itself.","","",3);
      };
      if (S.Week >= S.CruiseWeeks) S.Phase = 3;
    };
    $impl.ArrivalTick = function (S) {
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      O.$assign(Sc.Orbits[S.D.Orbit]);
      S.HalfDone = false;
      if (S.A.DvInsert > 0) {
        if (S.DvLeft < (S.A.DvInsert * 0.98)) {
          S.LostAtArrival = true;
          S.Alive = false;
          $impl.LogEvent(S,3,"Not enough propellant to stop",'Braking into "' + O.Name + '" needs ' + pas.TsFmt.FmtDv(S.A.DvInsert) + ", but only " + pas.TsFmt.FmtDv(S.DvLeft) + " was left in the tanks after the overweight spacecraft was drained to fit its rocket. It sailed past.","","This is why mass margin matters: it protects the propellant, and the propellant is the mission.",2);
          $impl.EndMission(S,"Could not enter orbit");
          return;
        };
        if ($impl.Rnd(S) >= S.A.InsertSuccess) {
          S.LostAtArrival = true;
          S.Alive = false;
          $impl.LogEvent(S,3,"Arrival failed","Something went wrong during the make-or-break arrival manoeuvre and the spacecraft was lost.","","Japan's Akatsuki missed Venus in 2010 when its main engine failed mid-burn. Its team waited five years and got it into orbit on the second try with small thrusters.",2);
          $impl.EndMission(S,"Lost on arrival");
          return;
        };
        S.DvLeft = S.DvLeft - S.A.DvInsert;
        if (O.ExtraYears > 0) {
          $impl.LogEvent(S,1,"Captured, then aerobraked into orbit",'The engine burn worked, and months of skimming the upper atmosphere shrank the orbit to "' + O.Name + '". ' + pas.TsFmt.FmtDv(S.DvLeft) + " of speed change remains.","","",2)}
         else $impl.LogEvent(S,1,"Arrived: " + O.Name,"The arrival burn worked. " + pas.TsFmt.FmtDv(S.DvLeft) + " of speed change remains for staying in orbit.","","",2);
      } else $impl.LogEvent(S,1,"On station: " + O.Name,"The spacecraft is checked out and ready for science.","","",3);
      if (Sc.ArriveBy) {
        if (S.Late) {
          $impl.LogEvent(S,2,"Arrived after the flyby","Apophis has already passed Earth. The chance to watch Earth's gravity reshape it has gone, but there is still an asteroid to study.","","",0)}
         else $impl.LogEvent(S,1,"Arrived before the flyby","The spacecraft is alongside Apophis with time to map it before Earth's gravity takes hold.","","",0);
      };
      S.Phase = 4;
      S.SciWeek = 0;
    };
    $impl.EarthDistance = function (S) {
      var Result = 0.0;
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      var Mid = 0.0;
      var Amp = 0.0;
      var Days = 0.0;
      var FlybyYear = 0.0;
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      O.$assign(Sc.Orbits[S.D.Orbit]);
      if (Sc.NearEarth) {
        Result = O.RangeKm / 1.495978707E8}
       else if (Sc.SynodicDays <= 0) {
        Result = Sc.EarthMaxAU}
       else {
        Mid = (Sc.EarthMinAU + Sc.EarthMaxAU) / 2;
        Amp = (Sc.EarthMaxAU - Sc.EarthMinAU) / 2;
        Days = S.Week * 7;
        if (Sc.ArriveBy) {
          FlybyYear = (Sc.DeadlineYears + 0.08) - S.LaunchYear;
          Result = Mid - (Amp * Math.cos((2 * Math.PI * (Days - (FlybyYear * 365.25))) / Sc.SynodicDays));
        } else Result = Mid - (Amp * Math.cos((2 * Math.PI * (Days + S.PhaseDays)) / Sc.SynodicDays));
      };
      return Result;
    };
    $impl.Anomaly = function (S) {
      var R = 0.0;
      var I = 0;
      var Adcs = pas.TsTypes.TPart.$new();
      var Comp = pas.TsTypes.TPart.$new();
      Adcs.$assign(pas.TsCatalog.Parts[2][S.D.Part[2]]);
      Comp.$assign(pas.TsCatalog.Parts[4][S.D.Part[4]]);
      S.Anomalies += 1;
      R = $impl.Rnd(S);
      if (R < S.A.FatalShare) {
        S.Alive = false;
        $impl.LogEvent(S,3,"Fatal failure","A fault in the power system cut off the spacecraft for good, " + pas.TsFmt.FmtYears(S.SciWeek / 52) + " into science operations.","","Roughly one fault in five ends a mission. Redundancy, a higher risk class, halves that share.",2);
        $impl.EndMission(S,"Lost to a hardware failure");
      } else if (R < (S.A.FatalShare + 0.36)) {
        I = $impl.RandomAlive(S);
        if ((I >= 0) && ($impl.AliveCount(S) > 1)) {
          S.InstrAlive[I] = false;
          S.InstrLost += 1;
          $impl.RecomputeCap(S);
          $impl.LogEvent(S,3,"Instrument failed: " + pas.TsCatalog.Instruments[I].Name,"It stopped responding and could not be revived. Science it had already gathered is safe.","","",1);
        } else {
          S.SciQuality = S.SciQuality * 0.7;
          $impl.LogEvent(S,3,"Instrument degraded","A detector fault leaves your instrument working at reduced sensitivity.","","",1);
        };
      } else if ((R < (S.A.FatalShare + 0.58)) && (S.PointTier >= 1)) {
        if (Math.round(Adcs.B) === 1) {
          $impl.LogEvent(S,1,"Reaction wheel failed, spare took over","One wheel seized. The fourth wheel you paid for took its place and pointing is unaffected.","","This is what redundancy buys.",2)}
         else {
          S.PointTier = 0;
          S.RateFactor = S.RateFactor * 0.7;
          $impl.RecomputeCap(S);
          $impl.LogEvent(S,3,"Reaction wheel failed","With only two wheels left the spacecraft can no longer hold steady. Sharp instruments are blurred and the antenna wanders.","","Kepler lost its second wheel in 2013 and could no longer do its original job.",2);
        };
      } else {
        if (Comp.Tier >= 2) {
          S.SafeWeeks = S.SafeWeeks + 1}
         else S.SafeWeeks = S.SafeWeeks + 3;
        $impl.LogEvent(S,2,"Computer fault: safe mode","The flight computer hit an error and put the spacecraft into safe mode. Controllers are working to bring it back.","","Safe mode saves the spacecraft, but every day in it is a day without science.",3);
      };
    };
    $impl.AskOps = function (S, Kind) {
      var Sc = pas.TsTypes.TScenario.$new();
      var Src = "";
      var T = "";
      var X = "";
      var I = 0;
      var N = 0;
      var Ext = 0;
      var W = pas.TsTypes.TSpaceWeather.$new();
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      var $tmp = Kind;
      if ($tmp === 6) {
        Src = "";
        T = "Forecasters report a solar eruption heading your way.";
        N = rtl.length(pas.TsScenarios.SpaceWeather);
        if (N > 0) {
          I = pas.System.Trunc($impl.Rnd(S) * N);
          if (I >= N) I = N - 1;
          W.$assign(pas.TsScenarios.SpaceWeather[I]);
          T = T + " It is modelled on a real one: a " + pas.TsScenarios.WeatherLabel(W) + ".";
          Src = "NASA DONKI space weather database (" + pas.TsScenarios.SpaceWeatherSource + ")";
        };
        $impl.Ask(S,Kind,"Solar storm warning",T,Src,"Operators often put spacecraft into safe mode to ride out a storm. During the 2003 Halloween storms a radiation instrument on Mars Odyssey was destroyed.",3);
        $impl.Opt(S,"Go to safe mode for a week","Lose one week of science. No risk.");
        $impl.Opt(S,"Keep observing","A chance of damage, and a chance of rare data.");
      } else if ($tmp === 7) {
        $impl.Ask(S,Kind,"A reaction wheel is running hot","Telemetry shows rising friction in one of the wheels that point the spacecraft.","","Kepler lost two of its four wheels. Engineers reinvented the mission as K2, balancing the telescope against the pressure of sunlight.",2);
        $impl.Opt(S,"Rest it: fewer turns for two months","About 20 % less science for eight weeks.");
        $impl.Opt(S,"Carry on as normal","A 40 % chance that the wheel fails.");
      } else if ($tmp === 8) {
        $impl.Ask(S,Kind,"Ground antenna out of service","The dish you rely on is going offline for six weeks of repairs.","","In 2020 the only antenna able to command Voyager 2 was switched off for 11 months of upgrades. The ground is part of the mission too.",3);
        $impl.Opt(S,"Buy time on another network","Costs " + pas.TsFmt.FmtMoney(pas.TsTypes.MaxD(0.6,0.012 * S.A.DevCostM)) + ". No data lost.");
        $impl.Opt(S,"Wait it out","Half the downlink for six weeks. The recorder must hold the backlog.");
      } else if ($tmp === 9) {
        if (Sc.Id === "earth") {
          T = "A volcano has just erupted";
          X = "A new eruption has started inside your coverage. Catching it early would be valuable to people on the ground.";
        } else if (Sc.Id === "moon") {
          T = "A surprise in the data";
          X = "One shadowed crater shows a far stronger hydrogen signal than predicted. It is not on the observing plan.";
        } else if (Sc.Id === "mars") {
          T = "A fresh impact crater";
          X = "A new crater has punched through the dust and exposed bright ice. It will fade within months.";
        } else if (Sc.Id === "apophis") {
          T = "Boulders are moving";
          X = "Images show boulders shifting on the surface. Nobody has ever watched this happen.";
        } else {
          T = "A possible plume";
          X = "A faint glow above the edge of Europa could be water vapour venting from the ocean below.";
        };
        $impl.Ask(S,Kind,T,X,"","The best discoveries are rarely in the plan. Good missions keep some fuel, time and data volume in hand for surprises.",1);
        $impl.Opt(S,"Re-plan and investigate","Two slower weeks and some propellant, for a chance of a major result.");
        $impl.Opt(S,"Stay on the plan","Nothing changes.");
      } else if ($tmp === 10) {
        Ext = rtl.trunc(S.PlanWeeks / 2);
        if (Ext < 13) Ext = 13;
        $impl.Ask(S,Kind,"Extended mission?","The planned mission is complete and the spacecraft is healthy. The science team asks to keep going. " + "So far you have " + pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the science goal and have spent " + pas.TsFmt.FmtMoney($mod.SimFinalCost(S)) + " of a " + pas.TsFmt.FmtMoney(S.A.CapM) + " cap.","","Extended missions are the best bargain in space science: the spacecraft is already built and already there. Mars Odyssey has worked for over 20 years on a 3-year plan.",0);
        $impl.Opt(S,"Extend by " + pas.TsFmt.FmtYears(Ext / 52),"Operations cost about " + pas.TsFmt.FmtMoney((S.A.OpsPerYearM * Ext) / 52) + ". More science, with diminishing returns.");
        $impl.Opt(S,"End on schedule","Bank the result.");
      } else {
        $impl.Ask(S,11,"Lunar eclipse ahead","Next week Earth's shadow will sweep across the Moon. The spacecraft will be in darkness for about five hours, " + "far longer than a normal orbit night, and your battery cannot carry it that long.","","Lunar Reconnaissance Orbiter switches off its instruments and warms itself up before every lunar eclipse.",2);
        $impl.Opt(S,"Power down and wait","Lose a week of science.");
        $impl.Opt(S,"Stay on and hope","An even chance of damaging the battery for good.");
      };
    };
    $impl.ScienceTick = function (S) {
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      var Prop = pas.TsTypes.TPart.$new();
      var M = 0;
      var Years = 0.0;
      var Deg = 0.0;
      var SolarNow = 0.0;
      var RtgNow = 0.0;
      var Ecl = 0.0;
      var GenAvg = 0.0;
      var PF = 0.0;
      var Ops = 0.0;
      var GenWeek = 0.0;
      var Dist = 0.0;
      var Rate = 0.0;
      var LinkWeek = 0.0;
      var Down = 0.0;
      var Lost = 0.0;
      var FW = 0.0;
      var Tau = 0.0;
      var DC = 0.0;
      var CapNow = 0.0;
      var PAnom = 0.0;
      var Need = 0.0;
      var Ev = pas.TsTypes.TEarthEvent.$new();
      var Seen = false;
      var K = 0;
      Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
      O.$assign(Sc.Orbits[S.D.Orbit]);
      Prop.$assign(pas.TsCatalog.Parts[1][S.D.Part[1]]);
      for (K = 6; K <= 9; K++) if (!S.Used[K] && (S.DecWeek[K] >= 0) && (S.SciWeek >= S.DecWeek[K])) {
        if ((K === 7) && (S.PointTier < 1)) {
          S.Used[K] = true;
          continue;
        };
        $impl.AskOps(S,K);
        return;
      };
      if ((Sc.Id === "moon") && !S.Used[11] && (S.SciWeek >= S.DecWeek[11]) && (S.SciWeek >= 20)) {
        Need = (pas.TsTypes.MaxD(0,S.A.LoadAvgW - S.A.RtgW) * 5) / 0.8;
        if (S.D.BatteryWh >= Need) {
          S.Used[11] = true;
          $impl.LogEvent(S,1,"Sailed through a lunar eclipse","Earth's shadow covered the Moon for five hours. Your " + pas.TsFmt.FmtNum(S.D.BatteryWh,0) + " Wh battery carried the spacecraft through.","","Sizing the battery for the worst night, not the usual one, paid off.",2);
        } else {
          $impl.AskOps(S,11);
          return;
        };
      };
      Years = S.SciWeek / 52;
      Deg = 0.025;
      if (O.RadLevel >= 2) Deg = 0.06;
      SolarNow = S.A.SolarW * pas.TsTypes.MaxD(0.3,1 - (Deg * (Years + (0.5 * S.A.CruiseYears)))) * pas.TsTypes.MaxD(0.2,1 - S.SolarLoss);
      RtgNow = S.A.RtgW * Math.pow(1 - 0.03,Years + S.A.CruiseYears);
      Ecl = O.EclipseFrac;
      GenAvg = RtgNow + ((SolarNow * (1 - Ecl)) / ((1 - Ecl) + (Ecl / 0.85)));
      PF = 1;
      if (S.A.LoadAvgW > 0) PF = pas.TsTypes.Clamp(GenAvg / S.A.LoadAvgW,0,1);
      if (!S.BatteryAged && (S.A.BatteryNeedWh > 0) && ((S.D.BatteryWh * (1 - (0.04 * Years))) < S.A.BatteryNeedWh)) {
        S.BatteryAged = true;
        $impl.LogEvent(S,2,"Battery has aged","After " + pas.TsFmt.FmtYears(Years) + " of charging and draining, the battery can no longer run everything through the longest eclipses. " + "Instruments now switch off in the dark.","","Batteries lose capacity with every cycle. Spare capacity on day one is what keeps a mission whole in year three.",2);
      };
      if (S.BatteryAged) PF = PF * 0.85;
      Ops = 1;
      if (S.SafeWeeks > 0) {
        Ops = 0;
        S.SafeWeeks -= 1;
        S.SafeTotal += 1;
      };
      if (S.SlowWeeks > 0) {
        Ops = Ops * 0.8;
        S.SlowWeeks -= 1;
      };
      GenWeek = pas.TsEngine.DataGenGbitDay(S.D,S.InstrAlive) * 7 * PF * Ops;
      Dist = $impl.EarthDistance(S);
      Rate = pas.TsEngine.LinkRateMbps(S.D,Dist,S.PointTier) * S.RateFactor;
      LinkWeek = (Rate * S.A.ContactHr * 3600 * 7) / 1000;
      if (S.BlackoutWeeks > 0) {
        LinkWeek = 0;
        S.BlackoutWeeks -= 1;
      } else if (S.HalfLinkWeeks > 0) {
        LinkWeek = LinkWeek * 0.5;
        S.HalfLinkWeeks -= 1;
      };
      S.StorageGbit = S.StorageGbit + GenWeek;
      Down = pas.TsTypes.MinD(S.StorageGbit,LinkWeek);
      S.StorageGbit = S.StorageGbit - Down;
      Lost = 0;
      if (S.StorageGbit > S.A.StorageGbit) {
        Lost = S.StorageGbit - S.A.StorageGbit;
        S.StorageGbit = S.A.StorageGbit;
      };
      S.GenGbit = S.GenGbit + GenWeek;
      S.DownGbit = S.DownGbit + Down;
      S.LostGbit = S.LostGbit + Lost;
      FW = 1;
      if (GenWeek > 0) FW = Math.pow(pas.TsTypes.Clamp(Down / GenWeek,0,3),0.7);
      if (Ops > 0) for (M = 0; M <= 8; M++) {
        Tau = (Sc.TauYears * O.TauFactor) / pas.TsTypes.MaxD(0.03,PF * FW * Ops);
        DC = (1 - S.Completion[M]) * (1 - Math.exp(-(1 / 52) / Tau));
        S.Completion[M] = S.Completion[M] + DC;
        CapNow = S.Cap[M] * S.SciQuality;
        if ((S.DustWeeks > 0) && ((M === 0) || (M === 1) || (M === 2))) CapNow = CapNow * 0.3;
        S.Realized[M] = S.Realized[M] + ((CapNow / 100) * DC);
      };
      if (S.DustWeeks > 0) S.DustWeeks -= 1;
      S.SciencePct = $impl.ScienceNow(S);
      S.PowerSum = S.PowerSum + PF;
      if (Prop.Tier > 0) S.DvLeft = S.DvLeft - (O.DvPerYear / 52);
      S.OpsCostM = S.OpsCostM + (S.A.OpsPerYearM / 52);
      K = rtl.length(S.HistScience);
      S.HistScience = rtl.arraySetLength(S.HistScience,0.0,K + 1);
      S.HistPower = rtl.arraySetLength(S.HistPower,0.0,K + 1);
      S.HistData = rtl.arraySetLength(S.HistData,0.0,K + 1);
      S.HistStore = rtl.arraySetLength(S.HistStore,0.0,K + 1);
      S.HistDv = rtl.arraySetLength(S.HistDv,0.0,K + 1);
      S.HistScience[K] = S.SciencePct;
      S.HistPower[K] = PF * 100;
      if (GenWeek > 0) {
        S.HistData[K] = pas.TsTypes.Clamp(Down / GenWeek,0,1) * 100}
       else S.HistData[K] = 100;
      if (S.A.StorageGbit > 0) {
        S.HistStore[K] = (S.StorageGbit / S.A.StorageGbit) * 100}
       else S.HistStore[K] = 0;
      if (S.DvStart > 0) {
        S.HistDv[K] = pas.TsTypes.Clamp(S.DvLeft / S.DvStart,0,1) * 100}
       else S.HistDv[K] = 0;
      S.SciWeek += 1;
      S.Week += 1;
      if (Sc.UsesEonet && (rtl.length(pas.TsScenarios.EarthEvents) > 0)) {
        Ev.$assign(pas.TsScenarios.EarthEvents[S.EarthIdx % rtl.length(pas.TsScenarios.EarthEvents)]);
        S.EarthIdx += 1;
        Seen = pas.TsScenarios.EventVisible(O,Ev.Lat,Ev.Lon) && (Ops > 0);
        if (Seen) {
          Seen = false;
          for (M = 0; M <= 8; M++) if ((pas.TsScenarios.CategorySuit(Ev.Category,M) >= 0.5) && (S.Cap[M] > 20)) Seen = true;
        };
        if (Seen) {
          S.EventsSeen += 1;
          if ((S.EventsSeen % 7) === 1) $impl.LogEvent(S,4,"Observed: " + Ev.Title,pas.TsScenarios.CategoryLabel(Ev.Category) + " at " + pas.TsFmt.FmtNum(Math.abs(Ev.Lat),1) + " deg " + pas.System.Copy("NS",1 + ((Ev.Lat < 0) + 0),1) + ", reported " + pas.TsFmt.NiceDate(Ev.Date) + ". Your instruments caught it and the data went to responders.","Real event: " + pas.TsScenarios.EarthEventsSource,"",1);
        };
      };
      if ((Sc.Id === "mars") && ((S.Week - S.ConjCycle) > 40) && (Dist > (Sc.EarthMaxAU * 0.985))) {
        S.ConjCycle = S.Week;
        S.BlackoutWeeks = 2;
        $impl.LogEvent(S,2,"Solar conjunction","Mars has moved behind the Sun as seen from Earth. For two weeks no reliable signal can get through. " + "Everything recorded has to wait in the " + pas.TsFmt.FmtData(S.A.StorageGbit) + " recorder.","","This happens every 26 months. Storage is what bridges the gap.",3);
      };
      if ((Sc.Id === "mars") && !S.DustDone && (S.SciWeek > 20) && (S.D.Difficulty !== 0) && ($impl.Rnd(S) < 0.012)) {
        S.DustDone = true;
        S.DustWeeks = 8;
        if (S.Cap[6] > 20) {
          S.BonusPct = S.BonusPct + 2;
          $impl.LogEvent(S,2,"Global dust storm","Dust has wrapped the whole planet. Cameras see almost nothing for two months, but your atmospheric instruments are having the time of their lives.","","Mariner 9 arrived in the middle of a storm like this in 1971 and simply waited for it to clear.",1);
        } else $impl.LogEvent(S,2,"Global dust storm","Dust has wrapped the whole planet. Cameras and spectrometers see almost nothing for two months.","","Mariner 9 arrived in the middle of a storm like this in 1971 and simply waited for it to clear.",1);
      };
      if (Sc.UsesApophis && !S.FlybyDone && !S.Late && ($mod.SimMissionYear(S) >= (Sc.DeadlineYears + 0.08))) {
        S.FlybyDone = true;
        $impl.LogEvent(S,4,"Flyby day","Apophis is sweeping past Earth at " + pas.TsFmt.FmtNum(pas.TsScenarios.ApophisVelKmS,2) + " km/s, " + pas.TsFmt.FmtNum(pas.TsScenarios.ApophisMissKm,0) + " km from the centre of the planet. Your spacecraft is alongside, recording Earth's gravity at work.","Real figures: NASA NeoWs / JPL close-approach data for " + pas.TsFmt.NiceDate(pas.TsScenarios.ApophisDate),"",1);
      };
      if (!S.HalfDone && (S.SciWeek >= rtl.trunc(S.PlanWeeks / 2)) && (S.PlanWeeks >= 20)) {
        S.HalfDone = true;
        $impl.LogEvent(S,0,"Halfway through the plan",pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the science goal so far. " + pas.TsFmt.FmtData(S.DownGbit) + " sent home, " + pas.TsFmt.FmtPct(S.PowerSum / S.SciWeek) + " of the power needed.","","",1);
      };
      $impl.SpaceWeatherTick(S,1,true);
      if (S.A.LifeLimitYears < 900) if (S.A.LifeLimitWhy === "radiation damage to the electronics") {
        S.Dose = S.Dose + ((1 / 52) / S.A.LifeLimitYears);
        if (S.Dose >= S.DoseLimit) {
          S.Alive = false;
          $impl.LogEvent(S,3,"Radiation finally won","After " + pas.TsFmt.FmtYears(S.SciWeek / 52) + " in the radiation belts the electronics have taken all they can. The spacecraft has gone silent.","","Every mission to Jupiter is a race between the science and the radiation dose.",2);
          $impl.EndMission(S,"Electronics destroyed by radiation");
          return;
        };
      };
      if ((S.DragLimitYears > 0) && ((S.SciWeek / 52) >= S.DragLimitYears)) {
        S.Alive = false;
        $impl.LogEvent(S,2,"Re-entry","With no engine to fight it, air drag has pulled the satellite down. It burned up after " + pas.TsFmt.FmtYears(S.SciWeek / 52) + ".","","Low orbits clean themselves up, but only propulsion lets you choose when.",3);
        $impl.EndMission(S,"Orbit decayed");
        return;
      };
      if ((Prop.Tier > 0) && (O.DvPerYear > 0) && (S.DvLeft <= 0)) {
        S.Alive = false;
        $impl.LogEvent(S,2,"Out of propellant","The tanks are empty after " + pas.TsFmt.FmtYears(S.SciWeek / 52) + ". Without fuel the orbit can no longer be held and the mission ends.","","Propellant is a mission's lifetime. Every unplanned manoeuvre shortens it.",2);
        $impl.EndMission(S,"Ran out of propellant");
        return;
      };
      PAnom = 1 - Math.exp((-S.A.AnomalyRate * S.FailMult) / 52);
      if (S.D.Difficulty === 0) PAnom = PAnom * 0.5;
      if ($impl.Rnd(S) < PAnom) {
        $impl.Anomaly(S);
        if (S.Phase === 5) return;
      };
      if (S.SciWeek >= S.PlanWeeks) {
        if (!S.Used[10]) {
          $impl.AskOps(S,10)}
         else {
          $impl.LogEvent(S,1,"Mission complete","Operations ended as planned after " + pas.TsFmt.FmtYears(S.SciWeek / 52) + " of science.","","",0);
          $impl.EndMission(S,"Completed");
        };
      };
    };
  };
},["SysUtils","Math","TsCatalog","TsScenarios","TsEngine","TsFmt"]);
rtl.module("TsScore",["System","TsTypes","TsSim"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  rtl.recNewT(this,"TInsight",function () {
    this.Tone = 0;
    this.Title = "";
    this.Text = "";
    this.Tip = "";
    this.$eq = function (b) {
      return (this.Tone === b.Tone) && (this.Title === b.Title) && (this.Text === b.Text) && (this.Tip === b.Tip);
    };
    this.$assign = function (s) {
      this.Tone = s.Tone;
      this.Title = s.Title;
      this.Text = s.Text;
      this.Tip = s.Tip;
      return this;
    };
  });
  rtl.recNewT(this,"TScoreCard",function () {
    this.Science = 0.0;
    this.Survival = 0.0;
    this.Budget = 0.0;
    this.Engineering = 0.0;
    this.Efficiency = 0.0;
    this.Total = 0;
    this.Stars = 0;
    this.Grade = "";
    this.Title = "";
    this.Outcome = "";
    this.OutcomeText = "";
    this.FinalCostM = 0.0;
    this.CapM = 0.0;
    this.SciencePct = 0.0;
    this.ReturnFrac = 0.0;
    this.PowerAvg = 0.0;
    this.YearsFlown = 0.0;
    this.YearsPlanned = 0.0;
    this.Analog = 0;
    this.AnalogText = "";
    this.RolesMet = 0;
    this.$new = function () {
      var r = Object.create(this);
      r.Insights = [];
      r.RoleMet = rtl.arraySetLength(null,false,4);
      r.RoleResult = rtl.arraySetLength(null,"",4);
      return r;
    };
    this.$eq = function (b) {
      return (this.Science === b.Science) && (this.Survival === b.Survival) && (this.Budget === b.Budget) && (this.Engineering === b.Engineering) && (this.Efficiency === b.Efficiency) && (this.Total === b.Total) && (this.Stars === b.Stars) && (this.Grade === b.Grade) && (this.Title === b.Title) && (this.Outcome === b.Outcome) && (this.OutcomeText === b.OutcomeText) && (this.FinalCostM === b.FinalCostM) && (this.CapM === b.CapM) && (this.SciencePct === b.SciencePct) && (this.ReturnFrac === b.ReturnFrac) && (this.PowerAvg === b.PowerAvg) && (this.YearsFlown === b.YearsFlown) && (this.YearsPlanned === b.YearsPlanned) && (this.Insights === b.Insights) && (this.Analog === b.Analog) && (this.AnalogText === b.AnalogText) && rtl.arrayEq(this.RoleMet,b.RoleMet) && rtl.arrayEq(this.RoleResult,b.RoleResult) && (this.RolesMet === b.RolesMet);
    };
    this.$assign = function (s) {
      this.Science = s.Science;
      this.Survival = s.Survival;
      this.Budget = s.Budget;
      this.Engineering = s.Engineering;
      this.Efficiency = s.Efficiency;
      this.Total = s.Total;
      this.Stars = s.Stars;
      this.Grade = s.Grade;
      this.Title = s.Title;
      this.Outcome = s.Outcome;
      this.OutcomeText = s.OutcomeText;
      this.FinalCostM = s.FinalCostM;
      this.CapM = s.CapM;
      this.SciencePct = s.SciencePct;
      this.ReturnFrac = s.ReturnFrac;
      this.PowerAvg = s.PowerAvg;
      this.YearsFlown = s.YearsFlown;
      this.YearsPlanned = s.YearsPlanned;
      this.Insights = rtl.arrayRef(s.Insights);
      this.Analog = s.Analog;
      this.AnalogText = s.AnalogText;
      this.RoleMet = s.RoleMet.slice(0);
      this.RoleResult = s.RoleResult.slice(0);
      this.RolesMet = s.RolesMet;
      return this;
    };
  });
  this.ScoreWeightScience = 0.45;
  this.ScoreWeightSurvival = 0.15;
  this.ScoreWeightBudget = 0.15;
  this.ScoreWeightEngineering = 0.15;
  this.ScoreWeightEfficiency = 0.10;
  this.ScoreMission = function (S) {
    var Result = $mod.TScoreCard.$new();
    var C = $mod.TScoreCard.$new();
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var A = pas.TsTypes.TAnalysis.$new();
    var L = pas.TsTypes.TLauncher.$new();
    var R = 0;
    var M = 0;
    var Prim = 0;
    var I = 0;
    var OrigPlan = 0;
    var BigI = 0;
    var Over = 0.0;
    var MassG = 0.0;
    var PowerG = 0.0;
    var DataG = 0.0;
    var RelG = 0.0;
    var Ratio = 0.0;
    var Best = 0.0;
    var Dist = 0.0;
    var BigData = 0.0;
    var V = 0.0;
    var HasLv = false;
    var Nm = "";
    Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
    O.$assign(Sc.Orbits[S.D.Orbit]);
    A.$assign(S.A);
    C.Insights = rtl.arraySetLength(C.Insights,$mod.TInsight,0);
    HasLv = S.D.Launcher >= 0;
    if (HasLv) L.$assign(pas.TsCatalog.Launchers[S.D.Launcher]);
    C.FinalCostM = pas.TsSim.SimFinalCost(S);
    C.CapM = A.CapM;
    C.SciencePct = S.SciencePct;
    if (S.GenGbit > 0) {
      C.ReturnFrac = pas.TsTypes.Clamp(S.DownGbit / S.GenGbit,0,1)}
     else C.ReturnFrac = A.DataReturn;
    if (S.SciWeek > 0) {
      C.PowerAvg = S.PowerSum / S.SciWeek}
     else C.PowerAvg = 0;
    OrigPlan = Math.round(S.D.LifeYears * 52);
    if (OrigPlan < 1) OrigPlan = 1;
    C.YearsFlown = S.SciWeek / 52;
    C.YearsPlanned = S.D.LifeYears;
    C.Science = pas.TsTypes.Clamp(S.SciencePct,0,100);
    if (S.LostAtLaunch || S.LostAtArrival) {
      C.Survival = 0}
     else C.Survival = pas.TsTypes.Clamp(S.SciWeek / OrigPlan,0,1) * 100;
    Over = (C.FinalCostM - C.CapM) / C.CapM;
    if (S.D.Sandbox || (Over <= 0)) {
      C.Budget = 100}
     else C.Budget = pas.TsTypes.Clamp(100 - (Over * 400),0,100);
    if (A.MassMargin >= 0.2) {
      MassG = 100}
     else if (A.MassMargin >= 0.1) {
      MassG = 80}
     else if (A.MassMargin >= 0) {
      MassG = 50}
     else MassG = 0;
    if (A.PowerMargin >= 0.3) {
      PowerG = 100}
     else if (A.PowerMargin >= 0.2) {
      PowerG = 85}
     else if (A.PowerMargin >= 0) {
      PowerG = 55}
     else PowerG = 0;
    DataG = C.ReturnFrac * 100;
    RelG = pas.TsTypes.Clamp(A.SuccessProb,0,1) * 100;
    C.Engineering = (MassG + PowerG + DataG + RelG) / 4;
    Ratio = (S.SciencePct / 100) / pas.TsTypes.MaxD(0.05,C.FinalCostM / C.CapM);
    C.Efficiency = pas.TsTypes.Clamp(70 * Ratio,0,100);
    C.Total = Math.round(10 * ((0.45 * C.Science) + (0.15 * C.Survival) + (0.15 * C.Budget) + (0.15 * C.Engineering) + (0.1 * C.Efficiency)));
    if ((S.SciencePct < Sc.ThresholdPct) && (C.Total > 619)) C.Total = 619;
    C.Grade = $mod.GradeOf(C.Total);
    C.Stars = $mod.StarsOf(C.Total);
    var $tmp = C.Stars;
    if ($tmp === 5) {
      C.Title = "Flagship-class triumph"}
     else if ($tmp === 4) {
      C.Title = "Outstanding mission"}
     else if ($tmp === 3) {
      C.Title = "Solid success"}
     else if ($tmp === 2) {
      C.Title = "Partial success"}
     else if ($tmp === 1) {
      C.Title = "Hard lessons"}
     else {
      C.Title = "Back to the drawing board";
    };
    if (S.LostAtLaunch) {
      C.Outcome = "Lost at launch";
      C.OutcomeText = "The rocket failed and the spacecraft never reached space.";
    } else if (S.LostAtArrival) {
      C.Outcome = "Lost on arrival";
      C.OutcomeText = "The spacecraft crossed the gap but could not enter its science orbit.";
    } else if (S.SciencePct >= 100) {
      C.Outcome = "Full mission success";
      C.OutcomeText = "The baseline science goal was met in full: " + pas.TsFmt.FmtNum(S.SciencePct,0) + " %.";
    } else if (S.SciencePct >= Sc.ThresholdPct) {
      C.Outcome = "Mission success";
      C.OutcomeText = "The mission passed its minimum (threshold) science of " + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " % and returned " + pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the full goal.";
    } else if (!S.Alive) {
      C.Outcome = "Mission cut short";
      C.OutcomeText = S.EndReason + " after " + pas.TsFmt.FmtYears(C.YearsFlown) + ", with " + pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the science goal. The minimum for success was " + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " %.";
    } else {
      C.Outcome = "Below minimum science";
      C.OutcomeText = "The spacecraft worked, but returned only " + pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the science goal. The minimum for success was " + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " %.";
    };
    if (S.LostAtLaunch && HasLv) $impl.AddInsight(C,3,"The rocket failed",L.Name + " succeeds about " + pas.TsFmt.FmtPct(L.Reliability) + " of the time, so this was a " + pas.TsFmt.FmtPct(1 - L.Reliability) + " roll of the dice. It was bad luck, but it was also a risk you chose.","Compare the reliability of each launcher with its price. For an irreplaceable spacecraft, a proven rocket is cheap insurance.");
    if (S.LostAtArrival) $impl.AddInsight(C,3,"The arrival burn was the mission","Everything depends on one long engine burn at the far end. Yours had a " + pas.TsFmt.FmtPct(A.InsertSuccess) + " chance of working with " + pas.TsFmt.FmtDv(A.DvInsert) + " needed and " + pas.TsFmt.FmtDv(S.DvStart) + " in the tanks at launch.","Keep at least 10 % launch mass margin so the propellant is never drained, and consider a route or orbit that needs a smaller burn.");
    if (!S.LostAtLaunch && !S.LostAtArrival) {
      if ((S.GenGbit > 0) && (C.ReturnFrac < 0.85)) {
        BigI = -1;
        BigData = 0;
        for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
          I = $l;
          if ((I <= (rtl.length(S.D.Instr) - 1)) && S.D.Instr[I] && pas.TsEngine.InstrumentOffered(S.D.Scenario,I)) {
            V = pas.TsCatalog.Instruments[I].DataMbps * pas.TsCatalog.Instruments[I].Duty;
            if (V > BigData) {
              BigData = V;
              BigI = I;
            };
          };
        };
        Nm = "Your instruments";
        if (BigI >= 0) Nm = "The " + pas.TsCatalog.Instruments[BigI].Name + " alone";
        $impl.AddInsight(C,2,"Only " + pas.TsFmt.FmtPct(C.ReturnFrac) + " of the data came home","The instruments recorded " + pas.TsFmt.FmtData(S.GenGbit) + " but the radio link could carry just " + pas.TsFmt.FmtData(S.DownGbit) + ". " + pas.TsFmt.FmtData(S.LostGbit) + " was overwritten before it could be sent. " + Nm + " produced the most data. From " + Sc.Body + " the average rate was " + pas.TsFmt.FmtRate(A.RateAvgMbps) + ".","Data rate grows with dish area, transmitter power, band and ground-station size, and falls with the square of distance. " + "Upgrade the link, or fly fewer data-hungry instruments.");
      } else if (S.GenGbit > 0) $impl.AddInsight(C,0,"Every bit came home","The link kept up with the instruments: " + pas.TsFmt.FmtData(S.DownGbit) + " returned, " + pas.TsFmt.FmtPct(C.ReturnFrac) + " of what was recorded.","");
      if ((S.SciWeek > 4) && (C.PowerAvg < 0.95)) {
        $impl.AddInsight(C,2,"Short of power " + pas.TsFmt.FmtPct(1 - C.PowerAvg) + " of the time","You launched with a power margin of " + pas.TsFmt.FmtPct(A.PowerMargin) + ". Solar panels fade every year" + " and by the end the spacecraft could not run everything at once, so instruments took turns.","Start with about 30 % power margin. It looks like waste on day one and like wisdom in year three.")}
       else if (A.PowerMargin > 1.5) $impl.AddInsight(C,1,"More power than you could use","The power system made " + pas.TsFmt.FmtPower(A.GenAvgW) + " against a need of " + pas.TsFmt.FmtPower(A.LoadAvgW) + ". That spare array cost mass and money.","Trim the array to about 30 % margin and spend the saving on science.");
      if (!S.Alive && (S.SciWeek < OrigPlan)) $impl.AddInsight(C,2,"Ended early: " + S.EndReason,"The spacecraft flew " + pas.TsFmt.FmtYears(C.YearsFlown) + " of a planned " + pas.TsFmt.FmtYears(C.YearsPlanned) + ".","Look at what ended it. Radiation needs hardened parts and shielding, drag and station-keeping need propellant, and random failures need backups.");
      Prim = pas.TsScenarios.PrimaryMeasure(Sc);
      if (O.Coverage < 0.5) $impl.AddInsight(C,2,"The orbit missed most of the targets",'"' + O.Name + '" reaches only ' + pas.TsFmt.FmtPct(O.Coverage) + " of what this mission came to study. " + O.Why,"Choose the orbit for the science first, then build the spacecraft to reach it.");
      if (A.Capability[Prim] < 35) $impl.AddInsight(C,2,"Weak on the main objective","This mission is mostly about " + pas.TsTypes.MeasureName[Prim] + ", and your payload scored only " + pas.TsFmt.FmtNum(A.Capability[Prim],0) + " out of 100 for it from this orbit.","Pick the instrument that is strongest in " + pas.TsTypes.MeasureName[Prim] + " and an orbit where it works well.");
      if (S.InstrLost > 0) $impl.AddInsight(C,1,pas.TsFmt.Plural(S.InstrLost,"instrument was","instruments were") + " lost along the way","Failures, storms or late mass cuts removed part of your payload. Science already gathered was kept.","A higher risk class, radiation protection and healthy mass margin all make this less likely.");
      Best = 0;
      for (M = 0; M <= 8; M++) if (S.Completion[M] > Best) Best = S.Completion[M];
      if ((Best > 0.93) && (S.SciencePct < 90)) {
        $impl.AddInsight(C,1,"The survey was finished, but the payload was thin","You flew long enough to complete " + pas.TsFmt.FmtPct(Best) + " of what your instruments could ever do. More time would not have helped: " + "the limit was what was on board and where it could see.","A richer payload or a better orbit would raise the ceiling. A shorter mission would have saved operations money.")}
       else if ((Best < 0.6) && S.Alive) $impl.AddInsight(C,1,"Still plenty left to discover","By the end the instruments had completed only " + pas.TsFmt.FmtPct(Best) + " of their survey.","A longer mission, more power or a better data link would have let them finish.");
    };
    if (!S.D.Sandbox && (C.FinalCostM > C.CapM)) {
      $impl.AddInsight(C,2,"Over budget by " + pas.TsFmt.FmtMoney(C.FinalCostM - C.CapM),"The mission cost " + pas.TsFmt.FmtMoney(C.FinalCostM) + " against a cap of " + pas.TsFmt.FmtMoney(C.CapM) + ". Surprises during the mission cost " + pas.TsFmt.FmtMoney(S.EventCostM) + " and you had set aside " + pas.TsFmt.FmtMoney(A.CostReserve) + " for them.","Hold about 25 % in reserve and leave room under the cap for it.")}
     else if (S.EventCostM > (A.CostReserve + 0.01)) {
      $impl.AddInsight(C,1,"Reserves ran out","Surprises cost " + pas.TsFmt.FmtMoney(S.EventCostM) + " and only " + pas.TsFmt.FmtMoney(A.CostReserve) + " had been set aside. Slack under the cap saved you.","Next time plan the reserve in, do not rely on luck.")}
     else if (!S.LostAtLaunch) $impl.AddInsight(C,0,"Finished " + pas.TsFmt.FmtMoney(C.CapM - C.FinalCostM) + " under the cap","Final cost " + pas.TsFmt.FmtMoney(C.FinalCostM) + ". Surprises cost " + pas.TsFmt.FmtMoney(S.EventCostM) + " and your " + pas.TsFmt.FmtMoney(A.CostReserve) + " reserve covered them.","");
    if (HasLv && (A.MassMargin > 0.75) && !L.Rideshare) {
      $impl.AddInsight(C,1,"You bought more rocket than you needed","The spacecraft used " + pas.TsFmt.FmtPct(1 - A.MassMargin) + " of what " + L.Name + " can lift, for " + pas.TsFmt.FmtMoney(A.CostLaunch) + ".","A smaller launcher or a shared ride could free up money for instruments.")}
     else if (HasLv && (A.MassMargin < 0.1) && (A.MassMargin >= 0)) $impl.AddInsight(C,1,"You launched with almost no mass margin","Only " + pas.TsFmt.FmtPct(A.MassMargin) + " spare, and the spacecraft then grew by " + pas.TsFmt.FmtMass(S.GrowthKg) + " during development.","Mass growth of 10 to 25 % is normal. Plan for it.");
    if (S.StormsRidden > 0) $impl.AddInsight(C,0,"Rode out " + pas.TsFmt.Plural(S.StormsRidden,"real solar storm","real solar storms"),"Particle storms recorded in NASA's DONKI database swept over the spacecraft. Its radiation protection held every time, " + "at the price of a little solar panel output.","");
    if (S.DragStorms > 0) $impl.AddInsight(C,1,pas.TsFmt.Plural(S.DragStorms,"real geomagnetic storm","real geomagnetic storms") + " raised the drag","Each storm in NASA's DONKI record swelled Earth's upper atmosphere and slowed your low-flying satellite a little, " + "costing propellant or orbit lifetime.","A higher orbit feels less drag. Propulsion lets you make up for it.");
    if (S.ExtendedWeeks > 0) $impl.AddInsight(C,0,"The extended mission paid off","Flying on for another " + pas.TsFmt.FmtYears(S.ExtendedWeeks / 52) + " cost only the operations budget, because the spacecraft was already built and already there.","");
    C.Analog = -1;
    C.AnalogText = "";
    Best = 1.0e9;
    for (var $l1 = 0, $end1 = rtl.length(Sc.Analogs) - 1; $l1 <= $end1; $l1++) {
      I = $l1;
      if ((Sc.Analogs[I].MassKg > 0) && (Sc.Analogs[I].CostM > 0)) {
        Dist = Math.abs(Math.log(pas.TsTypes.MaxD(1,S.DryKg + S.PropKg) / Sc.Analogs[I].MassKg)) + Math.abs(Math.log(pas.TsTypes.MaxD(1,C.FinalCostM) / Sc.Analogs[I].CostM));
        if (Dist < Best) {
          Best = Dist;
          C.Analog = I;
        };
      };
    };
    if (C.Analog >= 0) C.AnalogText = "Your " + pas.TsFmt.FmtMass(S.DryKg + S.PropKg) + ", " + pas.TsFmt.FmtMoney(C.FinalCostM) + " spacecraft with " + pas.TsFmt.Plural(A.InstrumentCount,"instrument","instruments") + " is closest in scale to " + Sc.Analogs[C.Analog].Name + " (" + Sc.Analogs[C.Analog].Agency + ", " + Sc.Analogs[C.Analog].Year + "): " + pas.TsFmt.FmtMass(Sc.Analogs[C.Analog].MassKg) + ", about " + pas.TsFmt.FmtMoney(Sc.Analogs[C.Analog].CostM) + ".";
    C.RoleMet[0] = ((C.FinalCostM <= C.CapM) || S.D.Sandbox) && !S.Late;
    if (C.RoleMet[0]) {
      C.RoleResult[0] = "On budget (" + pas.TsFmt.FmtMoney(C.FinalCostM) + ") and on time."}
     else if (S.Late) {
      C.RoleResult[0] = "The deadline was missed."}
     else C.RoleResult[0] = "Over the cap by " + pas.TsFmt.FmtMoney(C.FinalCostM - C.CapM) + ".";
    C.RoleMet[1] = S.SciencePct >= 85;
    C.RoleResult[1] = pas.TsFmt.FmtNum(S.SciencePct,0) + " % of the science goal.";
    C.RoleMet[2] = (A.MassMargin >= 0.10) && (A.PowerMargin >= 0.20) && !(S.LostAtArrival || (!S.Alive && !S.LostAtLaunch && (S.SciWeek < OrigPlan)));
    C.RoleResult[2] = "Mass margin " + pas.TsFmt.FmtPct(A.MassMargin) + ", power margin " + pas.TsFmt.FmtPct(A.PowerMargin);
    if (S.LostAtArrival || (!S.Alive && !S.LostAtLaunch && (S.SciWeek < OrigPlan))) {
      C.RoleResult[2] = C.RoleResult[2] + ", but the spacecraft was lost early."}
     else C.RoleResult[2] = C.RoleResult[2] + ".";
    C.RoleMet[3] = (C.ReturnFrac >= 0.90) && !(S.LostAtLaunch || S.LostAtArrival);
    C.RoleResult[3] = pas.TsFmt.FmtPct(C.ReturnFrac) + " of the recorded data returned.";
    if (S.LostAtLaunch || S.LostAtArrival) C.RoleResult[3] = "No science operations took place.";
    C.RolesMet = 0;
    for (R = 0; R <= 3; R++) if (C.RoleMet[R]) C.RolesMet += 1;
    Result.$assign(C);
    return Result;
  };
  this.GradeOf = function (Total) {
    var Result = "";
    if (Total >= 920) {
      Result = "S"}
     else if (Total >= 850) {
      Result = "A"}
     else if (Total >= 740) {
      Result = "B"}
     else if (Total >= 620) {
      Result = "C"}
     else if (Total >= 480) {
      Result = "D"}
     else Result = "F";
    return Result;
  };
  this.StarsOf = function (Total) {
    var Result = 0;
    if (Total >= 920) {
      Result = 5}
     else if (Total >= 850) {
      Result = 4}
     else if (Total >= 740) {
      Result = 3}
     else if (Total >= 620) {
      Result = 2}
     else if (Total >= 480) {
      Result = 1}
     else Result = 0;
    return Result;
  };
  this.RoleGoalText = function (R) {
    var Result = "";
    var $tmp = R;
    if ($tmp === 0) {
      Result = "Finish within the cost cap and meet the deadline."}
     else if ($tmp === 1) {
      Result = "Return at least 85 % of the science goal."}
     else if ($tmp === 2) {
      Result = "Launch with at least 10 % mass margin and 20 % power margin, and keep the spacecraft alive."}
     else {
      Result = "Get at least 90 % of the recorded data home.";
    };
    return Result;
  };
  this.RoleForecast = function (R, A, D) {
    var Result = false;
    var $tmp = R;
    if ($tmp === 0) {
      Result = ((A.CostTotal <= A.CapM) || D.Sandbox) && !A.MissedDeadline}
     else if ($tmp === 1) {
      Result = A.SciencePct >= 85}
     else if ($tmp === 2) {
      Result = (A.MassMargin >= 0.10) && (A.PowerMargin >= 0.20)}
     else {
      Result = A.DataReturn >= 0.90;
    };
    return Result;
  };
  $mod.$implcode = function () {
    $impl.AddInsight = function (C, ATone, ATitle, AText, ATip) {
      var N = 0;
      N = rtl.length(C.Insights);
      C.Insights = rtl.arraySetLength(C.Insights,$mod.TInsight,N + 1);
      C.Insights[N].Tone = ATone;
      C.Insights[N].Title = ATitle;
      C.Insights[N].Text = AText;
      C.Insights[N].Tip = ATip;
    };
  };
},["SysUtils","Math","TsCatalog","TsScenarios","TsEngine","TsFmt"]);
rtl.module("WebState",["System","SysUtils","TsTypes","TsSim","TsScore"],function () {
  "use strict";
  var $mod = this;
  this.TScreen = {"0": "scTitle", scTitle: 0, "1": "scSetup", scSetup: 1, "2": "scBrief", scBrief: 2, "3": "scLab", scLab: 3, "4": "scReview", scReview: 4, "5": "scMission", scMission: 5, "6": "scReport", scReport: 6, "7": "scLog", scLog: 7};
  this.TabCount = 7;
  this.TabName = ["Orbit","Payload","Spacecraft","Power","Comms and data","Launch","Plan"];
  this.TabIcon = ["orbit","flask","wrench","bolt","dish","rocket","flag"];
  this.TabRole = [1,1,2,2,3,0,0];
  this.Screen = 0;
  this.Scen = 0;
  this.Difficulty = 1;
  this.Sandbox = false;
  this.Players = 1;
  this.PlayerName = rtl.arraySetLength(null,"",4);
  this.D = pas.TsTypes.TDesign.$new();
  this.A = pas.TsTypes.TAnalysis.$new();
  this.PrevA = pas.TsTypes.TAnalysis.$new();
  this.HasDesign = false;
  this.HasPrev = false;
  this.LabTab = 0;
  this.Votes = rtl.arraySetLength(null,false,4);
  this.Sim = pas.TsSim.TSimState.$new();
  this.HasSim = false;
  this.Card = pas.TsScore.TScoreCard.$new();
  this.HasCard = false;
  this.SharedNote = "";
  this.RoleOwner = function (R) {
    var Result = 0;
    Result = 0;
    var $tmp = $mod.Players;
    if ($tmp === 2) {
      if ((R === 2) || (R === 3)) Result = 1}
     else if ($tmp === 3) {
      var $tmp1 = R;
      if ($tmp1 === 1) {
        Result = 0}
       else if ($tmp1 === 2) {
        Result = 1}
       else {
        Result = 2;
      };
    } else if ($tmp === 4) {
      var $tmp2 = R;
      if ($tmp2 === 0) {
        Result = 0}
       else if ($tmp2 === 1) {
        Result = 1}
       else if ($tmp2 === 2) {
        Result = 2}
       else {
        Result = 3;
      };
    };
    return Result;
  };
  this.RoleOwnerName = function (R) {
    var Result = "";
    if ($mod.Players <= 1) {
      Result = ""}
     else Result = $mod.PlayerName[$mod.RoleOwner(R)];
    return Result;
  };
  this.RoleClass = function (R) {
    var Result = "";
    var $tmp = R;
    if ($tmp === 0) {
      Result = "pm"}
     else if ($tmp === 1) {
      Result = "sci"}
     else if ($tmp === 2) {
      Result = "eng"}
     else {
      Result = "ops";
    };
    return Result;
  };
  this.PlayerRoles = function (P) {
    var Result = "";
    var R = 0;
    Result = "";
    for (R = 0; R <= 3; R++) if ($mod.RoleOwner(R) === P) {
      if (Result !== "") Result = Result + " and ";
      Result = Result + pas.TsTypes.RoleName[R];
    };
    return Result;
  };
  this.CrewText = function () {
    var Result = "";
    var I = 0;
    if ($mod.Players <= 1) {
      Result = $mod.PlayerName[0];
      if (Result === "") Result = "Solo";
      return Result;
    };
    Result = "";
    for (var $l = 0, $end = $mod.Players - 1; $l <= $end; $l++) {
      I = $l;
      if (I > 0) Result = Result + ", ";
      Result = Result + $mod.PlayerName[I];
    };
    return Result;
  };
  this.FindingTab = function (Code) {
    var Result = 0;
    if ((Code === "COVERAGE") || (Code === "DRAG")) {
      Result = 0}
     else if ((Code === "NO_INSTR") || (Code === "INSTR_COUNT") || (Code === "PAYLOAD_MASS") || (Code === "INSTR_BUS") || (Code === "PRIMARY") || (Code === "SCI_LOW") || (Code === "POINT_INSTR") || (Code === "COOLING") || (Code === "RADIO_HGA")) {
      Result = 1}
     else if ((Code === "DRY_LIMIT") || (Code === "ADCS_MTQ") || (Code === "ADCS_DESAT") || (Code === "THERMAL_COLD") || (Code === "THERMAL_HOT") || (Code === "RAD") || (Code === "LIFE_LIMIT") || (Code === "PROP_NEEDED") || (Code === "PROP_RUNAWAY") || (Code === "SEP_NA") || (Code === "DEORBIT")) {
      Result = 2}
     else if ((Code === "ARRAY_LIMIT") || (Code === "RTG_NA") || (Code === "NO_POWER") || (Code === "POWER_SHORT") || (Code === "POWER_THIN") || (Code === "POWER_BIG") || (Code === "BATTERY") || (Code === "BATTERY_THIN") || (Code === "SEP_POWER")) {
      Result = 3}
     else if ((Code === "UHF_DEEP") || (Code === "POINT_COMM") || (Code === "POINT_DISH") || (Code === "DATA") || (Code === "STORAGE")) {
      Result = 4}
     else if ((Code === "LV_NONE") || (Code === "LV_REACH") || (Code === "LV_HEAVY") || (Code === "LV_THIN") || (Code === "LV_BIG") || (Code === "RIDESHARE")) {
      Result = 5}
     else Result = 6;
    return Result;
  };
  this.Recalc = function () {
    if ($mod.HasDesign) {
      $mod.PrevA.$assign($mod.A);
      $mod.HasPrev = true;
    };
    $mod.A.$assign(pas.TsEngine.Analyze($mod.D));
    $mod.HasDesign = true;
  };
  this.ResetVotes = function () {
    var R = 0;
    for (R = 0; R <= 3; R++) $mod.Votes[R] = false;
  };
  this.NewSeed = function () {
    var Result = 0;
    Result = 1 + pas.System.Trunc(Math.random() * 2000000000);
    return Result;
  };
  $mod.$init = function () {
    $mod.PlayerName[0] = "Player 1";
    $mod.PlayerName[1] = "Player 2";
    $mod.PlayerName[2] = "Player 3";
    $mod.PlayerName[3] = "Player 4";
  };
},["JS","TsEngine"]);
rtl.module("WebStore",["System","JS","Web","SysUtils"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  rtl.recNewT(this,"TLogEntry",function () {
    this.Date = "";
    this.Scenario = "";
    this.ScenarioName = "";
    this.Grade = "";
    this.Outcome = "";
    this.Crew = "";
    this.Code = "";
    this.Score = 0;
    this.Players = 0;
    this.SciencePct = 0.0;
    this.CostM = 0.0;
    this.CapM = 0.0;
    this.$eq = function (b) {
      return (this.Date === b.Date) && (this.Scenario === b.Scenario) && (this.ScenarioName === b.ScenarioName) && (this.Grade === b.Grade) && (this.Outcome === b.Outcome) && (this.Crew === b.Crew) && (this.Code === b.Code) && (this.Score === b.Score) && (this.Players === b.Players) && (this.SciencePct === b.SciencePct) && (this.CostM === b.CostM) && (this.CapM === b.CapM);
    };
    this.$assign = function (s) {
      this.Date = s.Date;
      this.Scenario = s.Scenario;
      this.ScenarioName = s.ScenarioName;
      this.Grade = s.Grade;
      this.Outcome = s.Outcome;
      this.Crew = s.Crew;
      this.Code = s.Code;
      this.Score = s.Score;
      this.Players = s.Players;
      this.SciencePct = s.SciencePct;
      this.CostM = s.CostM;
      this.CapM = s.CapM;
      return this;
    };
  });
  this.LoadLog = function () {
    var Result = [];
    var Raw = "";
    var V = undefined;
    var Arr = null;
    var O = null;
    var I = 0;
    var N = 0;
    Result = rtl.arraySetLength(Result,$mod.TLogEntry,0);
    Raw = $impl.ReadKey($impl.LogKey);
    if (Raw === "") return Result;
    try {
      V = JSON.parse(Raw);
    } catch ($e) {
      return Result;
    };
    if (!rtl.isArray(V)) return Result;
    Arr = V;
    for (var $l = 0, $end = Arr.length - 1; $l <= $end; $l++) {
      I = $l;
      if (!rtl.isObject(Arr[I])) continue;
      O = Arr[I];
      N = rtl.length(Result);
      Result = rtl.arraySetLength(Result,$mod.TLogEntry,N + 1);
      Result[N].Date = $impl.StrOf(O,"date");
      Result[N].Scenario = $impl.StrOf(O,"scen");
      Result[N].ScenarioName = $impl.StrOf(O,"name");
      Result[N].Grade = $impl.StrOf(O,"grade");
      Result[N].Outcome = $impl.StrOf(O,"outcome");
      Result[N].Crew = $impl.StrOf(O,"crew");
      Result[N].Code = $impl.StrOf(O,"code");
      Result[N].Score = Math.round($impl.NumOf(O,"score"));
      Result[N].Players = Math.round($impl.NumOf(O,"players"));
      Result[N].SciencePct = $impl.NumOf(O,"sci");
      Result[N].CostM = $impl.NumOf(O,"cost");
      Result[N].CapM = $impl.NumOf(O,"cap");
    };
    return Result;
  };
  this.AddLogEntry = function (E) {
    var L = [];
    var Trimmed = [];
    var I = 0;
    var N = 0;
    L = $mod.LoadLog();
    N = rtl.length(L);
    L = rtl.arraySetLength(L,$mod.TLogEntry,N + 1);
    L[N].$assign(E);
    if (rtl.length(L) > 60) {
      Trimmed = rtl.arraySetLength(Trimmed,$mod.TLogEntry,60);
      for (I = 0; I <= 59; I++) Trimmed[I].$assign(L[(rtl.length(L) - 60) + I]);
      L = rtl.arrayRef(Trimmed);
    };
    $impl.SaveLog(L);
  };
  this.ClearLog = function () {
    try {
      window.localStorage.removeItem($impl.LogKey);
    } catch ($e) {
    };
  };
  this.LoadSetting = function (Key, Default) {
    var Result = "";
    Result = $impl.ReadKey($impl.SetPrefix + Key);
    if (Result === "") Result = Default;
    return Result;
  };
  this.SaveSetting = function (Key, Value) {
    $impl.WriteKey($impl.SetPrefix + Key,Value);
  };
  $mod.$implcode = function () {
    $impl.LogKey = "tradespace.log.v1";
    $impl.SetPrefix = "tradespace.set.";
    $impl.MaxEntries = 60;
    $impl.ReadKey = function (Key) {
      var Result = "";
      var V = undefined;
      Result = "";
      try {
        V = window.localStorage.getItem(Key);
        if (rtl.isString(V)) Result = "" + V;
      } catch ($e) {
        Result = "";
      };
      return Result;
    };
    $impl.WriteKey = function (Key, Value) {
      try {
        window.localStorage.setItem(Key,Value);
      } catch ($e) {
      };
    };
    $impl.StrOf = function (O, Name) {
      var Result = "";
      if (rtl.isString(O[Name])) {
        Result = "" + O[Name]}
       else Result = "";
      return Result;
    };
    $impl.NumOf = function (O, Name) {
      var Result = 0.0;
      if (rtl.isNumber(O[Name])) {
        Result = rtl.getNumber(O[Name])}
       else Result = 0;
      return Result;
    };
    $impl.SaveLog = function (L) {
      var Arr = null;
      var O = null;
      var I = 0;
      Arr = new Array();
      for (var $l = 0, $end = rtl.length(L) - 1; $l <= $end; $l++) {
        I = $l;
        O = new Object();
        O["date"] = L[I].Date;
        O["scen"] = L[I].Scenario;
        O["name"] = L[I].ScenarioName;
        O["grade"] = L[I].Grade;
        O["outcome"] = L[I].Outcome;
        O["crew"] = L[I].Crew;
        O["code"] = L[I].Code;
        O["score"] = L[I].Score;
        O["players"] = L[I].Players;
        O["sci"] = L[I].SciencePct;
        O["cost"] = L[I].CostM;
        O["cap"] = L[I].CapM;
        Arr.push(O);
      };
      $impl.WriteKey($impl.LogKey,JSON.stringify(Arr));
    };
  };
},[]);
rtl.module("WebNasa",["System","JS","Web","SysUtils","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  rtl.recNewT(this,"TNasaStatus",function () {
    this.Loaded = false;
    this.SnapshotDate = "";
    this.EonetCount = 0;
    this.EonetTotal = 0;
    this.EonetLive = false;
    this.DonkiCount = 0;
    this.DonkiFrom = "";
    this.DonkiTo = "";
    this.ApophisDays = 0;
    this.ApophisDate = "";
    this.$eq = function (b) {
      return (this.Loaded === b.Loaded) && (this.SnapshotDate === b.SnapshotDate) && (this.EonetCount === b.EonetCount) && (this.EonetTotal === b.EonetTotal) && (this.EonetLive === b.EonetLive) && (this.DonkiCount === b.DonkiCount) && (this.DonkiFrom === b.DonkiFrom) && (this.DonkiTo === b.DonkiTo) && (this.ApophisDays === b.ApophisDays) && (this.ApophisDate === b.ApophisDate);
    };
    this.$assign = function (s) {
      this.Loaded = s.Loaded;
      this.SnapshotDate = s.SnapshotDate;
      this.EonetCount = s.EonetCount;
      this.EonetTotal = s.EonetTotal;
      this.EonetLive = s.EonetLive;
      this.DonkiCount = s.DonkiCount;
      this.DonkiFrom = s.DonkiFrom;
      this.DonkiTo = s.DonkiTo;
      this.ApophisDays = s.ApophisDays;
      this.ApophisDate = s.ApophisDate;
      return this;
    };
  });
  this.NasaStatus = this.TNasaStatus.$new();
  this.LoadNasaData = function (OnChange) {
    $mod.NasaStatus.Loaded = false;
    $mod.NasaStatus.EonetLive = false;
    $mod.NasaStatus.ApophisDate = "2029-04-13";
    $mod.NasaStatus.ApophisDays = $mod.DaysUntil("2029-04-13");
    pas.TsScenarios.ApplyApophis($mod.NasaStatus.ApophisDays,38011,7.42,"2029-04-13");
    $impl.DoLoad(OnChange);
  };
  this.DaysUntil = function (IsoDate) {
    var Result = 0;
    Result = pas.TsFmt.DayNumber(IsoDate) - pas.TsFmt.DayNumber(pas.System.Copy((new Date()).toISOString(),1,10));
    return Result;
  };
  $mod.$implcode = function () {
    $impl.StrOf = function (O, Name) {
      var Result = "";
      if (rtl.isString(O[Name])) {
        Result = "" + O[Name]}
       else Result = "";
      return Result;
    };
    $impl.NumOf = function (O, Name) {
      var Result = 0.0;
      if (rtl.isNumber(O[Name])) {
        Result = rtl.getNumber(O[Name])}
       else if (rtl.isString(O[Name])) {
        Result = pas.TsFmt.ParseFloat("" + O[Name])}
       else Result = 0;
      return Result;
    };
    $impl.ApplyApophisFrom = function (O) {
      var D = "";
      D = $impl.StrOf(O,"approachDate");
      if (D === "") D = "2029-04-13";
      $mod.NasaStatus.ApophisDate = D;
      $mod.NasaStatus.ApophisDays = $mod.DaysUntil(D);
      pas.TsScenarios.ApplyApophis($mod.NasaStatus.ApophisDays,$impl.NumOf(O,"missKm"),$impl.NumOf(O,"relVelKmS"),D);
    };
    $impl.ApplySnapshot = function (Snap) {
      var Sec = null;
      var Arr = null;
      var O = null;
      var Ev = [];
      var Sw = [];
      var I = 0;
      var N = 0;
      $mod.NasaStatus.SnapshotDate = pas.System.Copy($impl.StrOf(Snap,"generated"),1,10);
      if (rtl.isObject(Snap["eonet"])) {
        Sec = Snap["eonet"];
        if (rtl.isArray(Sec["events"])) {
          Arr = Sec["events"];
          Ev = rtl.arraySetLength(Ev,pas.TsTypes.TEarthEvent,0);
          for (var $l = 0, $end = Arr.length - 1; $l <= $end; $l++) {
            I = $l;
            O = Arr[I];
            N = rtl.length(Ev);
            Ev = rtl.arraySetLength(Ev,pas.TsTypes.TEarthEvent,N + 1);
            Ev[N].Title = $impl.StrOf(O,"t");
            Ev[N].Category = $impl.StrOf(O,"c");
            Ev[N].Date = $impl.StrOf(O,"d");
            Ev[N].Lat = $impl.NumOf(O,"lat");
            Ev[N].Lon = $impl.NumOf(O,"lon");
          };
          $mod.NasaStatus.EonetCount = rtl.length(Ev);
          $mod.NasaStatus.EonetTotal = Math.round($impl.NumOf(Sec,"total"));
          $mod.NasaStatus.EonetLive = false;
          pas.TsScenarios.ApplyEarthEvents(Ev,"NASA EONET, " + pas.TsFmt.NiceDate($mod.NasaStatus.SnapshotDate));
        };
      };
      if (rtl.isObject(Snap["donki"])) {
        Sec = Snap["donki"];
        if (rtl.isArray(Sec["events"])) {
          Arr = Sec["events"];
          Sw = rtl.arraySetLength(Sw,pas.TsTypes.TSpaceWeather,0);
          for (var $l1 = 0, $end1 = Arr.length - 1; $l1 <= $end1; $l1++) {
            I = $l1;
            O = Arr[I];
            N = rtl.length(Sw);
            Sw = rtl.arraySetLength(Sw,pas.TsTypes.TSpaceWeather,N + 1);
            Sw[N].Kind = $impl.StrOf(O,"k");
            Sw[N].Date = $impl.StrOf(O,"d");
            Sw[N].ClassType = $impl.StrOf(O,"cls");
            Sw[N].Strength = pas.TsScenarios.WeatherStrength(Sw[N].Kind,Sw[N].ClassType);
          };
          $mod.NasaStatus.DonkiCount = rtl.length(Sw);
          $mod.NasaStatus.DonkiFrom = $impl.StrOf(Sec,"from");
          $mod.NasaStatus.DonkiTo = $impl.StrOf(Sec,"to");
          if (rtl.length(Sw) > 0) pas.TsScenarios.ApplySpaceWeather(Sw,"NASA DONKI, " + pas.TsFmt.NiceDate($mod.NasaStatus.DonkiFrom) + " to " + pas.TsFmt.NiceDate($mod.NasaStatus.DonkiTo));
        };
      };
      if (rtl.isObject(Snap["apophis"])) $impl.ApplyApophisFrom(Snap["apophis"]);
      $mod.NasaStatus.Loaded = true;
    };
    $impl.ParseEonetLive = function (Reply, Total) {
      var Result = [];
      var Arr = null;
      var Geo = null;
      var Cats = null;
      var Co = null;
      var Ring = null;
      var O = null;
      var G = null;
      var I = 0;
      var J = 0;
      var N = 0;
      var Fires = 0;
      var Step = 0;
      var Lon = 0.0;
      var Lat = 0.0;
      var Cat = "";
      Result = rtl.arraySetLength(Result,pas.TsTypes.TEarthEvent,0);
      Total.set(0);
      if (!rtl.isArray(Reply["events"])) return Result;
      Arr = Reply["events"];
      Total.set(Arr.length);
      Fires = 0;
      for (var $l = 0, $end = Arr.length - 1; $l <= $end; $l++) {
        I = $l;
        O = Arr[I];
        if (rtl.isArray(O["categories"]) && (O["categories"].length > 0) && ($impl.StrOf(O["categories"][0],"id") === "wildfires")) Fires += 1;
      };
      Step = rtl.trunc(Fires / 260);
      if (Step < 1) Step = 1;
      Fires = 0;
      for (var $l1 = 0, $end1 = Arr.length - 1; $l1 <= $end1; $l1++) {
        I = $l1;
        O = Arr[I];
        if (!(rtl.isArray(O["categories"]) && rtl.isArray(O["geometry"]))) continue;
        Cats = O["categories"];
        Geo = O["geometry"];
        if ((Cats.length === 0) || (Geo.length === 0)) continue;
        Cat = $impl.StrOf(Cats[0],"id");
        if (Cat === "wildfires") {
          Fires += 1;
          if ((Fires % Step) !== 0) continue;
        };
        G = Geo[Geo.length - 1];
        if (!rtl.isArray(G["coordinates"])) continue;
        Co = G["coordinates"];
        if ($impl.StrOf(G,"type") === "Point") {
          if (Co.length < 2) continue;
          Lon = rtl.getNumber(Co[0]);
          Lat = rtl.getNumber(Co[1]);
        } else {
          if ((Co.length === 0) || !rtl.isArray(Co[0])) continue;
          Ring = Co[0];
          if (Ring.length === 0) continue;
          Lon = 0;
          Lat = 0;
          for (var $l2 = 0, $end2 = Ring.length - 1; $l2 <= $end2; $l2++) {
            J = $l2;
            Lon = Lon + rtl.getNumber(Ring[J][0]);
            Lat = Lat + rtl.getNumber(Ring[J][1]);
          };
          Lon = Lon / Ring.length;
          Lat = Lat / Ring.length;
        };
        N = rtl.length(Result);
        Result = rtl.arraySetLength(Result,pas.TsTypes.TEarthEvent,N + 1);
        Result[N].Title = $impl.StrOf(O,"title");
        Result[N].Category = Cat;
        Result[N].Date = pas.System.Copy($impl.StrOf(G,"date"),1,10);
        Result[N].Lat = Lat;
        Result[N].Lon = Lon;
      };
      return Result;
    };
    $impl.DoLoad = async function (OnChange) {
      var Resp = null;
      var Txt = "";
      var Ev = [];
      var Total = 0;
      try {
        Resp = await window.fetch("data/nasa-snapshot.json");
        if (Resp.ok) {
          Txt = await Resp.text();
          $impl.ApplySnapshot(JSON.parse(Txt));
          if (OnChange != null) OnChange();
        };
      } catch ($e) {
        if (pas.SysUtils.Exception.isPrototypeOf($e)) {
          var E = $e;
          window.console.warn("NASA snapshot not loaded: " + E.fMessage);
        } else throw $e
      };
      try {
        Resp = await window.fetch("https://eonet.gsfc.nasa.gov/api/v3/events?days=30&status=all");
        if (Resp.ok) {
          Txt = await Resp.text();
          Ev = $impl.ParseEonetLive(JSON.parse(Txt),{get: function () {
              return Total;
            }, set: function (v) {
              Total = v;
            }});
          if (rtl.length(Ev) >= 30) {
            $mod.NasaStatus.EonetCount = rtl.length(Ev);
            $mod.NasaStatus.EonetTotal = Total;
            $mod.NasaStatus.EonetLive = true;
            $mod.NasaStatus.Loaded = true;
            pas.TsScenarios.ApplyEarthEvents(Ev,"NASA EONET, live " + pas.TsFmt.NiceDate(pas.System.Copy((new Date()).toISOString(),1,10)));
            if (OnChange != null) OnChange();
          };
        };
      } catch ($e) {
        if (pas.SysUtils.Exception.isPrototypeOf($e)) {
          var E = $e;
          window.console.warn("Live EONET refresh skipped: " + E.fMessage);
        } else throw $e
      };
    };
  };
},["TsScenarios","TsFmt"]);
rtl.module("WebDraw",["System","JS","Web","SysUtils","Math","TsTypes","TsSim"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.LoadImages = function () {
    $impl.ImgSky = $impl.NewImage("assets/launch_sky.jpg");
    $impl.ImgMap = $impl.NewImage("assets/earth_map.jpg");
    $impl.ImgCloud[0] = $impl.NewImage("assets/cloud_1.png");
    $impl.ImgCloud[1] = $impl.NewImage("assets/cloud_2.png");
    $impl.ImgCloud[2] = $impl.NewImage("assets/cloud_3.png");
  };
  this.Prep = function (Id, W, H, Ctx) {
    var Result = false;
    var C = null;
    Result = false;
    Ctx.set(null);
    C = document.getElementById(Id);
    if (C === null) return Result;
    if ((C.width !== (W * 2)) || (C.height !== (H * 2))) {
      C.width = W * 2;
      C.height = H * 2;
    };
    Ctx.set(C.getContext("2d"));
    Ctx.get().setTransform(2,0,0,2,0,0);
    Result = true;
    return Result;
  };
  this.DrawStars = function () {
    var C = null;
    var Ctx = null;
    var W = 0;
    var H = 0;
    var I = 0;
    var N = 0;
    var Seed = 0.0;
    var X = 0.0;
    var Y = 0.0;
    var R = 0.0;
    var A = 0.0;
    var G = null;
    C = document.getElementById("cv-stars");
    if (C === null) return;
    W = window.innerWidth;
    H = window.innerHeight;
    C.width = W;
    C.height = H;
    Ctx = C.getContext("2d");
    G = Ctx.createLinearGradient(0,0,0,H);
    G.addColorStop(0,"#0a1226");
    G.addColorStop(1,"#05070e");
    Ctx.fillStyle = G;
    Ctx.fillRect(0,0,W,H);
    Seed = 20261114;
    N = rtl.trunc((W * H) / 5200);
    for (var $l = 1, $end = N; $l <= $end; $l++) {
      I = $l;
      X = $impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) * W;
      Y = $impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) * H;
      R = 0.3 + ($impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) * 1.0);
      A = 0.2 + ($impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) * 0.6);
      if ((I % 9) === 0) {
        $impl.Disc(Ctx,X,Y,R,$impl.Rgba(160,200,255,A))}
       else if ((I % 13) === 0) {
        $impl.Disc(Ctx,X,Y,R,$impl.Rgba(255,225,180,A))}
       else $impl.Disc(Ctx,X,Y,R,$impl.Rgba(255,255,255,A));
    };
  };
  this.DrawOrbitView = function (Ctx, W, H, D, T) {
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var Cx = 0.0;
    var Cy = 0.0;
    var Rb = 0.0;
    var BodyKm = 0.0;
    var Rp = 0.0;
    var Ra = 0.0;
    var Lim = 0.0;
    var Inc = 0.0;
    var Omega = 0.0;
    var Tvis = 0.0;
    var M = 0.0;
    var Nu = 0.0;
    var E = 0.0;
    var X = 0.0;
    var Y = 0.0;
    var Dp = 0.0;
    var Xs = 0.0;
    var Ds = 0.0;
    var F = 0.0;
    var Body = "";
    var Label2 = "";
    var Flyby = false;
    var AtJupiter = false;
    Sc.$assign(pas.TsScenarios.Scenarios[D.Scenario]);
    O.$assign(Sc.Orbits[D.Orbit]);
    Ctx.clearRect(0,0,W,H);
    Cx = W * 0.5;
    Cy = H * 0.52;
    Rb = Math.min(W,H) * 0.17;
    Lim = Math.min(W * 0.47,H * 0.46);
    Body = Sc.Body;
    BodyKm = 6371;
    if (Body === "Moon") {
      BodyKm = 1737}
     else if (Body === "Mars") {
      BodyKm = 3390}
     else if (Body === "Apophis") {
      BodyKm = 0.17}
     else if (Body === "Europa") BodyKm = 1561;
    Flyby = O.TauFactor < 0.1;
    AtJupiter = (Sc.Id === "europa") && (O.Id !== "orbiter");
    $impl.DrawSunHint(Ctx,H);
    if (Flyby) {
      $impl.DrawBody(Ctx,Body,Cx,Cy + (H * 0.1),Rb * 0.8);
      Ctx.strokeStyle = $impl.ColLine;
      Ctx.lineWidth = 1.6;
      Ctx.setLineDash([5,4]);
      $impl.Line(Ctx,30,Cy - (H * 0.3),W - 10,Cy - (H * 0.12));
      Ctx.setLineDash([]);
      F = pas.System.Frac(T / 6);
      $impl.DrawProbe(Ctx,30 + (F * (W - 40)),(Cy - (H * 0.3)) + (F * H * 0.18),true);
      $impl.Txt(Ctx,"One pass at several km/s",W - 8,H - 10,$impl.FontSmall,$impl.ColMuted,"right");
      $impl.Txt(Ctx,pas.SysUtils.UpperCase(Body),30,H - 10,$impl.FontBig,$impl.ColText,"left");
      return;
    };
    if (AtJupiter) {
      Body = "Jupiter";
      Rb = Math.min(W,H) * 0.2;
      Ra = Lim;
      if (O.Id === "tour") {
        Rp = Rb * 1.9;
        Inc = (8 * Math.PI) / 180;
      } else {
        Rp = Rb * 1.15;
        Inc = (88 * Math.PI) / 180;
      };
      Omega = 0;
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rb * 1.9,Rb * 1.9,(2 * Math.PI) / 180,0,false,"rgba(255,255,255,0.25)");
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rp,Ra,Inc,Omega,false,$impl.ColLine);
      $impl.DrawBody(Ctx,Body,Cx,Cy,Rb);
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rb * 1.9,Rb * 1.9,(2 * Math.PI) / 180,0,true,"rgba(255,255,255,0.4)");
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rp,Ra,Inc,Omega,true,$impl.ColLine);
      $impl.OrbitPoint(pas.System.Frac(T / 23) * 2 * Math.PI,Rb * 1.9,Rb * 1.9,(2 * Math.PI) / 180,0,{get: function () {
          return X;
        }, set: function (v) {
          X = v;
        }},{get: function () {
          return Y;
        }, set: function (v) {
          Y = v;
        }},{get: function () {
          return Dp;
        }, set: function (v) {
          Dp = v;
        }},{get: function () {
          return Xs;
        }, set: function (v) {
          Xs = v;
        }},{get: function () {
          return Ds;
        }, set: function (v) {
          Ds = v;
        }});
      if (!((Dp > 0) && (Math.sqrt((X * X) + (Y * Y)) < Rb))) {
        $impl.Disc(Ctx,Cx + X,Cy + Y,4,"#f3e6cc");
        $impl.Txt(Ctx,"Europa",Cx + X + 7,(Cy + Y) - 6,$impl.FontSmall,$impl.ColMuted,"left");
      };
      Tvis = 11;
    } else {
      Rp = Rb * $impl.ScaleAlt(O.AltKm,BodyKm);
      Ra = Rb * $impl.ScaleAlt(O.ApoKm,BodyKm);
      if (Ra > Lim) {
        Rp = (Rp * Lim) / Ra;
        if (Rp < (Rb * 1.12)) Rp = Rb * 1.12;
        Ra = Lim;
      };
      Inc = (O.IncDeg * Math.PI) / 180;
      if (Inc > (Math.PI / 2)) Inc = (Math.PI / 2) - (Inc - (Math.PI / 2));
      Omega = -Math.PI / 2;
      if (O.IncDeg < 10) Omega = 0;
      if (Sc.Id === "europa") $impl.DrawBody(Ctx,"Jupiter",W * 0.93,H * 0.12,Math.min(W,H) * 0.3);
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rp,Ra,Inc,Omega,false,$impl.ColLine);
      $impl.DrawBody(Ctx,Body,Cx,Cy,Rb);
      $impl.DrawRing(Ctx,Cx,Cy,Rb,Rp,Ra,Inc,Omega,true,$impl.ColLine);
      Tvis = Math.max(4,Math.min(14,3 + (2.2 * Math.log(1 + O.PeriodHr))));
    };
    E = 0;
    if ((Ra + Rp) > 0) E = (Ra - Rp) / (Ra + Rp);
    M = pas.System.Frac(T / Tvis) * 2 * Math.PI;
    Nu = M + (2 * E * Math.sin(M)) + (1.25 * E * E * Math.sin(2 * M));
    $impl.OrbitPoint(Nu,Rp,Ra,Inc,Omega,{get: function () {
        return X;
      }, set: function (v) {
        X = v;
      }},{get: function () {
        return Y;
      }, set: function (v) {
        Y = v;
      }},{get: function () {
        return Dp;
      }, set: function (v) {
        Dp = v;
      }},{get: function () {
        return Xs;
      }, set: function (v) {
        Xs = v;
      }},{get: function () {
        return Ds;
      }, set: function (v) {
        Ds = v;
      }});
    if (!((Dp > 0) && (Math.sqrt((X * X) + (Y * Y)) < Rb))) $impl.DrawProbe(Ctx,Cx + X,Cy + Y,!((Xs > 0) && (Ds < Rb)));
    $impl.Txt(Ctx,pas.SysUtils.UpperCase(Sc.Body),30,H - 26,$impl.FontBig,$impl.ColText,"left");
    if (O.ApoKm > (O.AltKm * 1.05)) {
      Label2 = pas.TsFmt.FmtNum(O.AltKm,0) + " x " + pas.TsFmt.FmtNum(O.ApoKm,0) + " km"}
     else Label2 = pas.TsFmt.FmtNum(O.AltKm,0) + " km";
    $impl.Txt(Ctx,Label2 + "  |  tilt " + pas.TsFmt.FmtNum(O.IncDeg,0) + " deg  |  one lap " + pas.TsFmt.FmtAuto(O.PeriodHr) + " h",30,H - 10,$impl.FontSmall,$impl.ColMuted,"left");
    Ctx.fillStyle = "rgba(120,130,160,0.9)";
    Ctx.fillRect(W - 150,H - 17,14,3);
    $impl.Txt(Ctx,"in shadow " + pas.TsFmt.FmtPct(O.EclipseFrac),W - 132,H - 10,$impl.FontSmall,$impl.ColMuted,"left");
  };
  this.DrawCraft = function (Ctx, W, H, D, A) {
    var Bus = pas.TsTypes.TPart.$new();
    var Prop = pas.TsTypes.TPart.$new();
    var Ant = pas.TsTypes.TPart.$new();
    var Shield = pas.TsTypes.TPart.$new();
    var Band = pas.TsTypes.TPart.$new();
    var Cx = 0.0;
    var Cy = 0.0;
    var Bw = 0.0;
    var Bh = 0.0;
    var Pm = 0.0;
    var WingH = 0.0;
    var WingL = 0.0;
    var MaxL = 0.0;
    var AreaHalf = 0.0;
    var DishW = 0.0;
    var X = 0.0;
    var Y = 0.0;
    var Bx = 0.0;
    var By = 0.0;
    var I = 0;
    var N = 0;
    var Seg = 0;
    var K = 0;
    var Col = 0;
    var PerRow = 0;
    var Scaled = false;
    var Code = "";
    Bus.$assign(pas.TsCatalog.Parts[0][D.Part[0]]);
    Prop.$assign(pas.TsCatalog.Parts[1][D.Part[1]]);
    Ant.$assign(pas.TsCatalog.Parts[6][D.Part[6]]);
    Shield.$assign(pas.TsCatalog.Parts[5][D.Part[5]]);
    Band.$assign(pas.TsCatalog.Parts[7][D.Part[7]]);
    Ctx.clearRect(0,0,W,H);
    Ctx.strokeStyle = "rgba(90,209,255,0.07)";
    Ctx.lineWidth = 1;
    I = 0;
    while ((I * 17) < W) {
      $impl.Line(Ctx,(I * 17) + 0.5,0,(I * 17) + 0.5,H);
      I += 1;
    };
    I = 0;
    while ((I * 17) < H) {
      $impl.Line(Ctx,0,(I * 17) + 0.5,W,(I * 17) + 0.5);
      I += 1;
    };
    Cx = W / 2;
    Cy = H * 0.5;
    var $tmp = Bus.Tier;
    if ($tmp === 0) {
      Bw = 30;
      Pm = 40;
    } else if ($tmp === 1) {
      Bw = 48;
      Pm = 17;
    } else if ($tmp === 2) {
      Bw = 66;
      Pm = 9.5;
    } else {
      Bw = 84;
      Pm = 6.5;
    };
    Bh = Bw * 1.15;
    Scaled = false;
    if (D.SolarM2 > 0) {
      AreaHalf = D.SolarM2 / 2;
      WingH = Math.sqrt(AreaHalf / 2.6) * Pm;
      WingL = 2.6 * Math.sqrt(AreaHalf / 2.6) * Pm;
      MaxL = (W / 2) - (Bw / 2) - 16;
      if (WingL > MaxL) {
        WingH = (WingH * MaxL) / WingL;
        WingL = MaxL;
        Scaled = true;
      };
      if (WingH > (H * 0.5)) WingH = H * 0.5;
      if (WingH < 5) WingH = 5;
      Seg = Math.round(WingL / Math.max(10,WingH * 0.8));
      if (Seg < 1) Seg = 1;
      for (K = 0; K <= 1; K++) {
        if (K === 0) {
          X = Cx - (Bw / 2) - 8 - WingL}
         else X = Cx + (Bw / 2) + 8;
        Ctx.fillStyle = "rgba(40,90,170,0.45)";
        Ctx.fillRect(X,Cy - (WingH / 2),WingL,WingH);
        Ctx.strokeStyle = $impl.ColLine;
        Ctx.lineWidth = 1.2;
        Ctx.strokeRect(X,Cy - (WingH / 2),WingL,WingH);
        Ctx.strokeStyle = "rgba(90,209,255,0.45)";
        for (var $l = 1, $end = Seg - 1; $l <= $end; $l++) {
          I = $l;
          $impl.Line(Ctx,X + ((I * WingL) / Seg),Cy - (WingH / 2),X + ((I * WingL) / Seg),Cy + (WingH / 2));
        };
        Ctx.strokeStyle = $impl.ColLine;
        if (K === 0) {
          $impl.Line(Ctx,X + WingL,Cy,Cx - (Bw / 2),Cy)}
         else $impl.Line(Ctx,Cx + (Bw / 2),Cy,X,Cy);
      };
    };
    for (var $l1 = 0, $end1 = D.RtgCount - 1; $l1 <= $end1; $l1++) {
      I = $l1;
      X = Cx + (Bw / 2) + 14 + (I * 13);
      Y = Cy + (Bh / 2) + 6;
      Ctx.strokeStyle = "#ffb547";
      Ctx.lineWidth = 1.2;
      $impl.Line(Ctx,Cx + (Bw / 2),(Cy + (Bh / 2)) - 4,X,Y);
      Ctx.fillStyle = "rgba(255,181,71,0.25)";
      Ctx.fillRect(X - 4,Y,8,22);
      Ctx.strokeRect(X - 4,Y,8,22);
      $impl.Line(Ctx,X - 7,Y + 5,X + 7,Y + 5);
      $impl.Line(Ctx,X - 7,Y + 11,X + 7,Y + 11);
      $impl.Line(Ctx,X - 7,Y + 17,X + 7,Y + 17);
    };
    if (Prop.Tier > 0) {
      Ctx.strokeStyle = $impl.ColLine;
      Ctx.lineWidth = 1.2;
      Y = Cy + (Bh / 2);
      if (Prop.Tier === 4) {
        Ctx.fillStyle = "rgba(90,209,255,0.35)";
        Ctx.fillRect(Cx - 7,Y,14,6);
        Ctx.strokeRect(Cx - 7,Y,14,6);
        Ctx.fillStyle = "rgba(120,230,255,0.25)";
        Ctx.beginPath();
        Ctx.moveTo(Cx - 6,Y + 6);
        Ctx.lineTo(Cx + 6,Y + 6);
        Ctx.lineTo(Cx,Y + 26);
        Ctx.closePath();
        Ctx.fill();
      } else {
        K = 5 + (Prop.Tier * 2);
        Ctx.beginPath();
        Ctx.moveTo(Cx - (K * 0.5),Y);
        Ctx.lineTo(Cx + (K * 0.5),Y);
        Ctx.lineTo(Cx + K,Y + (K * 1.3));
        Ctx.lineTo(Cx - K,Y + (K * 1.3));
        Ctx.closePath();
        Ctx.fillStyle = "rgba(147,164,195,0.25)";
        Ctx.fill();
        Ctx.stroke();
      };
    };
    Bx = Cx - (Bw / 2);
    By = Cy - (Bh / 2);
    Ctx.fillStyle = "rgba(19,28,48,0.95)";
    Ctx.fillRect(Bx,By,Bw,Bh);
    Ctx.strokeStyle = $impl.ColLine;
    Ctx.lineWidth = 1.6;
    Ctx.strokeRect(Bx,By,Bw,Bh);
    if (Shield.Tier === 2) {
      Ctx.strokeStyle = "#ffb547";
      Ctx.lineWidth = 2;
      Ctx.strokeRect(Bx + 4,By + 4,Bw - 8,Bh - 8);
    } else if (Shield.Tier === 1) {
      Ctx.strokeStyle = "rgba(255,181,71,0.6)";
      Ctx.lineWidth = 1;
      Ctx.setLineDash([3,3]);
      Ctx.strokeRect(Bx + 4,By + 4,Bw - 8,Bh - 8);
      Ctx.setLineDash([]);
    };
    Ctx.strokeStyle = $impl.ColLine;
    Ctx.lineWidth = 1.4;
    if (Band.Tier === 4) {
      Ctx.fillStyle = "rgba(196,161,255,0.4)";
      Ctx.fillRect(Cx - 5,By - 10,10,10);
      Ctx.strokeStyle = "#c4a1ff";
      Ctx.strokeRect(Cx - 5,By - 10,10,10);
      Ctx.setLineDash([2,3]);
      $impl.Line(Ctx,Cx,By - 10,Cx + 26,By - 40);
      Ctx.setLineDash([]);
    } else if (Ant.A < 0.3) {
      Ctx.fillStyle = "rgba(90,209,255,0.3)";
      Ctx.fillRect(Cx - 5,By - 4,10,4);
      Ctx.strokeRect(Cx - 5,By - 4,10,4);
    } else {
      DishW = Math.max(12,Ant.A * Pm);
      if (DishW > (W * 0.5)) DishW = W * 0.5;
      Ctx.beginPath();
      Ctx.ellipse(Cx,By - 6,DishW / 2,Math.max(3,DishW * 0.17),0,0,Math.PI);
      Ctx.fillStyle = "rgba(90,209,255,0.18)";
      Ctx.fill();
      Ctx.stroke();
      $impl.Line(Ctx,Cx - (DishW / 2),By - 6,Cx + (DishW / 2),By - 6);
      $impl.Line(Ctx,Cx,By - 6,Cx,By - 6 - Math.max(6,DishW * 0.3));
      $impl.Disc(Ctx,Cx,By - 6 - Math.max(6,DishW * 0.3),1.8,$impl.ColLine);
    };
    N = A.InstrumentCount;
    if (N > 0) {
      PerRow = 2;
      if (Bus.Tier >= 2) PerRow = 3;
      if (Bus.Tier === 0) PerRow = 1;
      Col = 0;
      K = 0;
      for (var $l2 = 0, $end2 = rtl.length(pas.TsCatalog.Instruments) - 1; $l2 <= $end2; $l2++) {
        I = $l2;
        if ((I <= (rtl.length(A.InstrQuality) - 1)) && (A.InstrQuality[I] > 0)) {
          X = Bx + 4 + (Col * ((Bw - 8) / PerRow));
          Y = By + 5 + (K * 11);
          if ((Y + 10) > ((By + Bh) - 2)) break;
          if (A.InstrQuality[I] < 1) {
            Ctx.fillStyle = "rgba(255,181,71,0.35)"}
           else Ctx.fillStyle = "rgba(196,161,255,0.35)";
          Ctx.fillRect(X,Y,((Bw - 8) / PerRow) - 2,9);
          Code = $impl.InstrCode(pas.TsCatalog.Instruments[I].Id);
          if (((Bw - 8) / PerRow) < 26) Code = pas.System.Copy(Code,1,3);
          $impl.Txt(Ctx,Code,X + ((((Bw - 8) / PerRow) - 2) / 2),Y + 7.5,"7px ui-monospace, Consolas, monospace","#ffffff","center");
          Col += 1;
          if (Col >= PerRow) {
            Col = 0;
            K += 1;
          };
        };
      };
    };
    $impl.Txt(Ctx,pas.SysUtils.UpperCase(Bus.Name),8,16,$impl.FontSmall,$impl.ColMuted,"left");
    $impl.Txt(Ctx,"dry " + pas.TsFmt.FmtMass(A.DryKg) + "  fuel " + pas.TsFmt.FmtMass(A.PropKg),8,H - 8,$impl.FontSmall,$impl.ColMuted,"left");
    if (Scaled) {
      $impl.Txt(Ctx,"wings not to scale",W - 8,16,$impl.FontSmall,$impl.ColMuted,"right")}
     else if (D.SolarM2 > 0) $impl.Txt(Ctx,pas.TsFmt.FmtNum(D.SolarM2,1) + " m2 solar",W - 8,16,$impl.FontSmall,$impl.ColMuted,"right");
    if (D.RtgCount > 0) $impl.Txt(Ctx,pas.SysUtils.IntToStr(D.RtgCount) + " x RTG",W - 8,H - 8,$impl.FontSmall,"#ffb547","right");
  };
  this.DrawEarthMap = function (Ctx, W, H, D, ShowOrbit) {
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var I = 0;
    var X = 0.0;
    var Y = 0.0;
    var Lim = 0.0;
    var A = 0.0;
    var Lat = 0.0;
    var Lon = 0.0;
    var Ang = 0.0;
    var Az = 0.0;
    var La = 0.0;
    var Lo = 0.0;
    var IncEff = 0.0;
    var Th = 0.0;
    var La0 = 0.0;
    var Lo0 = 0.0;
    var Vis = false;
    Sc.$assign(pas.TsScenarios.Scenarios[D.Scenario]);
    O.$assign(Sc.Orbits[D.Orbit]);
    if ($impl.Ready($impl.ImgMap)) {
      Ctx.drawImage($impl.ImgMap,0,0,W,H)}
     else {
      Ctx.fillStyle = "#0b2545";
      Ctx.fillRect(0,0,W,H);
    };
    Ctx.fillStyle = "rgba(4,8,18,0.35)";
    Ctx.fillRect(0,0,W,H);
    Ctx.strokeStyle = "rgba(255,255,255,0.10)";
    Ctx.lineWidth = 1;
    for (I = 1; I <= 5; I++) $impl.Line(Ctx,0,(I * H) / 6,W,(I * H) / 6);
    for (I = 1; I <= 11; I++) $impl.Line(Ctx,(I * W) / 12,0,(I * W) / 12,H);
    if (ShowOrbit) {
      Ctx.fillStyle = "rgba(2,5,12,0.62)";
      if (O.IsGeo) {
        Ctx.beginPath();
        Ctx.rect(0,0,W,H);
        La0 = 0;
        Lo0 = (O.GeoLon * Math.PI) / 180;
        Ang = (62 * Math.PI) / 180;
        for (I = 0; I <= 72; I++) {
          Az = (I / 72) * 2 * Math.PI;
          La = Math.asin((Math.sin(La0) * Math.cos(Ang)) + (Math.cos(La0) * Math.sin(Ang) * Math.cos(Az)));
          Lo = Lo0 + Math.atan2(Math.sin(Az) * Math.sin(Ang) * Math.cos(La0),Math.cos(Ang) - (Math.sin(La0) * Math.sin(La)));
          X = ((((Lo * 180) / Math.PI) + 180) / 360) * W;
          Y = ((90 - ((La * 180) / Math.PI)) / 180) * H;
          if (I === 0) {
            Ctx.moveTo(X,Y)}
           else Ctx.lineTo(X,Y);
        };
        Ctx.closePath();
        Ctx.fill("evenodd");
        $impl.Disc(Ctx,((O.GeoLon + 180) / 360) * W,H / 2,4,"#ffffff");
      } else {
        if (O.IncDeg >= 90) {
          Lim = 86}
         else Lim = O.IncDeg + 4;
        Y = ((90 - Lim) / 180) * H;
        Ctx.fillRect(0,0,W,Y);
        Ctx.fillRect(0,H - Y,W,Y);
        Ctx.strokeStyle = "rgba(90,209,255,0.8)";
        Ctx.setLineDash([6,5]);
        $impl.Line(Ctx,0,Y,W,Y);
        $impl.Line(Ctx,0,H - Y,W,H - Y);
        Ctx.setLineDash([]);
        IncEff = O.IncDeg;
        if (IncEff > 90) IncEff = 180 - IncEff;
        Ctx.strokeStyle = "rgba(90,209,255,0.55)";
        Ctx.lineWidth = 1.3;
        Ctx.beginPath();
        for (I = 0; I <= 240; I++) {
          Th = (I / 120) * 2 * Math.PI;
          Lat = (Math.asin(Math.sin((IncEff * Math.PI) / 180) * Math.sin(Th)) * 180) / Math.PI;
          Lon = -180 + (pas.System.Frac(((I / 120) * (1 - (O.PeriodHr / 24))) + 0.08) * 360);
          X = ((Lon + 180) / 360) * W;
          Y = ((90 - Lat) / 180) * H;
          if ((I === 0) || (I === 120) || (Math.abs(Lon - Lo0) > 180)) {
            Ctx.moveTo(X,Y)}
           else Ctx.lineTo(X,Y);
          Lo0 = Lon;
        };
        Ctx.stroke();
      };
    };
    for (var $l = 0, $end = rtl.length(pas.TsScenarios.EarthEvents) - 1; $l <= $end; $l++) {
      I = $l;
      X = ((pas.TsScenarios.EarthEvents[I].Lon + 180) / 360) * W;
      Y = ((90 - pas.TsScenarios.EarthEvents[I].Lat) / 180) * H;
      Vis = !ShowOrbit || pas.TsScenarios.EventVisible(O,pas.TsScenarios.EarthEvents[I].Lat,pas.TsScenarios.EarthEvents[I].Lon);
      if (Vis) {
        A = 0.95}
       else A = 0.3;
      Ctx.globalAlpha = A;
      if (Vis) {
        $impl.Disc(Ctx,X,Y,2.4,$mod.CategoryColor(pas.TsScenarios.EarthEvents[I].Category))}
       else $impl.Disc(Ctx,X,Y,1.6,$mod.CategoryColor(pas.TsScenarios.EarthEvents[I].Category));
    };
    Ctx.globalAlpha = 1;
    if (ShowOrbit && (O.EventsTotal > 0)) {
      Ctx.fillStyle = "rgba(4,8,18,0.75)";
      Ctx.fillRect(6,H - 24,232,18);
      $impl.Txt(Ctx,"In view: " + pas.SysUtils.IntToStr(O.EventsSeen) + " of " + pas.SysUtils.IntToStr(O.EventsTotal) + " real events",12,H - 11,$impl.FontSmall,$impl.ColText,"left");
    };
  };
  this.DrawLaunch = function (Ctx, W, H, T, Size, Fail) {
    var G = null;
    var P = 0.0;
    var Tt = 0.0;
    var YOff = 0.0;
    var SkyA = 0.0;
    var Hgt = 0.0;
    var Wid = 0.0;
    var Rx = 0.0;
    var Ry = 0.0;
    var GroundY = 0.0;
    var Alt = 0.0;
    var Vel = 0.0;
    var Seed = 0.0;
    var Sx = 0.0;
    var Sy = 0.0;
    var Fire = 0.0;
    var BoostP = 0.0;
    var K = 0.0;
    var I = 0;
    var Msg = "";
    var Clock = "";
    var Blown = false;
    Tt = T - 3;
    P = pas.TsTypes.Clamp(Tt / 10,0,1);
    Blown = Fail && (T >= 7.2);
    G = Ctx.createLinearGradient(0,0,0,H);
    G.addColorStop(0,"#02040a");
    G.addColorStop(1,"#0b1730");
    Ctx.fillStyle = G;
    Ctx.fillRect(0,0,W,H);
    Seed = 4242;
    for (I = 1; I <= 90; I++) {
      Sx = $impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) * W;
      Sy = pas.System.Frac($impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}) + (P * 0.25)) * H;
      $impl.Disc(Ctx,Sx,Sy,0.4 + $impl.NextRand({get: function () {
          return Seed;
        }, set: function (v) {
          Seed = v;
        }}),$impl.Rgba(255,255,255,pas.TsTypes.Clamp((P - 0.3) * 1.6,0,0.9)));
    };
    YOff = P * P * H * 2.4;
    SkyA = pas.TsTypes.Clamp(1 - (P * 1.5),0,1);
    if (SkyA > 0) {
      Ctx.globalAlpha = SkyA;
      if ($impl.Ready($impl.ImgSky)) {
        Ctx.drawImage($impl.ImgSky,0,(-H * 0.25) + (YOff * 0.35),W,H * 1.25)}
       else {
        G = Ctx.createLinearGradient(0,0,0,H);
        G.addColorStop(0,"#5a6fd0");
        G.addColorStop(1,"#f2a37c");
        Ctx.fillStyle = G;
        Ctx.fillRect(0,0,W,H);
      };
      Ctx.globalAlpha = 1;
    };
    for (I = 0; I <= 2; I++) if ($impl.Ready($impl.ImgCloud[I]) && (P < 0.75)) {
      Ctx.globalAlpha = pas.TsTypes.Clamp(1 - (P * 1.4),0,0.9);
      Sy = (-H * (0.5 + (I * 0.75))) + (YOff * (1.5 + (I * 0.25)));
      Sx = (W * (0.05 + (I * 0.36))) - 60;
      Ctx.drawImage($impl.ImgCloud[I],Sx,Sy,260,150);
      Ctx.globalAlpha = 1;
    };
    GroundY = (H - 34) + (YOff * 2.6);
    if (GroundY < (H + 60)) {
      Ctx.fillStyle = "#0b0f17";
      Ctx.fillRect(0,GroundY,W,H);
      Ctx.strokeStyle = "#2a3142";
      Ctx.lineWidth = 2;
      Sx = (W / 2) + 34;
      $impl.Line(Ctx,Sx,GroundY,Sx,GroundY - 170);
      $impl.Line(Ctx,Sx + 12,GroundY,Sx + 12,GroundY - 170);
      for (I = 0; I <= 8; I++) {
        $impl.Line(Ctx,Sx,GroundY - (I * 20),Sx + 12,GroundY - (I * 20) - 20);
        $impl.Line(Ctx,Sx + 12,GroundY - (I * 20),Sx,GroundY - (I * 20) - 20);
      };
      if (Tt < 0.4) $impl.Line(Ctx,Sx,GroundY - 120,(W / 2) + 8,GroundY - 120);
    };
    var $tmp = Size;
    if ($tmp === 0) {
      Hgt = 96;
      Wid = 9;
    } else if ($tmp === 1) {
      Hgt = 124;
      Wid = 12;
    } else if ($tmp === 2) {
      Hgt = 150;
      Wid = 14;
    } else {
      Hgt = 168;
      Wid = 15;
    };
    Rx = W / 2;
    if (Tt < 0) {
      Ry = H - 36}
     else Ry = H - 36 - (pas.TsTypes.Clamp(Tt / 2.2,0,1) * H * 0.27) - (P * H * 0.06);
    if ((Tt > 0) && (Tt < 3)) Rx = Rx + (Math.sin(T * 55) * 0.9);
    if ((Tt > -0.6) && (P < 0.3)) for (I = 0; I <= 9; I++) {
      K = pas.TsTypes.Clamp((Tt + 0.6) / 2.5,0,1);
      $impl.Disc(Ctx,(W / 2) + ((I - 4.5) * 26 * K),GroundY - 6 - (Math.abs(I - 4.5) * 2),10 + (22 * K) + ((I % 3) * 5),$impl.Rgba(225,225,232,0.5 * (1 - (P * 3.2))));
    };
    Fire = 0;
    if (Tt > -0.5) Fire = 0.6 + (0.4 * Math.sin(T * 40));
    if (P >= 1) Fire = 0;
    BoostP = pas.TsTypes.Clamp((P - 0.6) / 0.25,0,1);
    if (!Blown) {
      $impl.DrawRocket(Ctx,Rx,Ry,Hgt,Wid,Size,(Size === 3) && (BoostP <= 0),Fire);
      if ((Size === 3) && (BoostP > 0) && (BoostP < 1)) for (I = 0; I <= 1; I++) {
        Ctx.save();
        Ctx.translate(Rx + (((I * 2) - 1) * ((Wid * 1.05) + (BoostP * 70))),(Ry - (Hgt * 0.3)) + (BoostP * 90));
        Ctx.rotate(((I * 2) - 1) * BoostP * 1.1);
        Ctx.fillStyle = "#d9dee8";
        Ctx.fillRect(-Wid * 0.42,-Hgt * 0.31,Wid * 0.84,Hgt * 0.62);
        Ctx.restore();
      };
    } else {
      K = pas.TsTypes.Clamp((T - 7.2) / 2.5,0,1);
      G = Ctx.createRadialGradient(Rx,Ry - (Hgt * 0.5),2,Rx,Ry - (Hgt * 0.5),30 + (K * 190));
      G.addColorStop(0,$impl.Rgba(255,255,255,0.95 * (1 - K)));
      G.addColorStop(0.4,$impl.Rgba(255,190,90,0.8 * (1 - K)));
      G.addColorStop(1,"rgba(255,90,30,0)");
      Ctx.fillStyle = G;
      Ctx.fillRect(0,0,W,H);
      Seed = 777;
      Ctx.strokeStyle = $impl.Rgba(230,230,240,1 - K);
      Ctx.lineWidth = 2;
      for (I = 1; I <= 22; I++) {
        Sx = (($impl.NextRand({get: function () {
            return Seed;
          }, set: function (v) {
            Seed = v;
          }}) * 2) - 1) * 240 * K;
        Sy = ((($impl.NextRand({get: function () {
            return Seed;
          }, set: function (v) {
            Seed = v;
          }}) * 2) - 1) * 170 * K) + (K * K * 120);
        $impl.Line(Ctx,Rx + Sx,(Ry - (Hgt * 0.5)) + Sy,Rx + (Sx * 1.08) + 3,(Ry - (Hgt * 0.5)) + (Sy * 1.08) + 4);
      };
    };
    Alt = 0;
    Vel = 0;
    if (Tt > 0) {
      Alt = 1.55 * Math.pow(Math.min(Tt,10),2.1);
      Vel = Math.min(7.8,0.0125 * Math.pow(Math.min(Tt,10),2.8));
    };
    if (Tt < 0) {
      Clock = "T-" + pas.SysUtils.IntToStr(pas.Math.Ceil(-Tt))}
     else Clock = "T+" + pas.TsFmt.FmtNum(Tt * 52,0) + " s";
    Ctx.fillStyle = "rgba(3,6,13,0.6)";
    Ctx.fillRect(10,10,168,62);
    $impl.Txt(Ctx,Clock,20,30,$impl.FontBig,$impl.ColText,"left");
    $impl.Txt(Ctx,"altitude " + pas.TsFmt.FmtNum(Alt,0) + " km",20,47,$impl.FontMid,$impl.ColText,"left");
    $impl.Txt(Ctx,"speed    " + pas.TsFmt.FmtNum(Vel,2) + " km/s",20,63,$impl.FontMid,$impl.ColText,"left");
    Msg = "";
    if (Tt < 0) {
      Msg = "All stations are go"}
     else if (Blown) {
      Msg = "LOSS OF VEHICLE"}
     else if (Tt < 1.6) {
      Msg = "LIFTOFF"}
     else if ((Tt > 3) && (Tt < 4.6)) {
      Msg = "Maximum aerodynamic pressure"}
     else if ((Size === 3) && (P > 0.6) && (P < 0.8)) {
      Msg = "Booster separation"}
     else if ((P > 0.82) && (P < 0.97)) {
      Msg = "Fairing jettisoned: the spacecraft sees space"}
     else if (P >= 1) Msg = "Spacecraft separation confirmed";
    if (Msg !== "") {
      Ctx.fillStyle = "rgba(3,6,13,0.6)";
      Ctx.fillRect((W / 2) - 190,H - 30,380,22);
      if (Blown) {
        $impl.Txt(Ctx,Msg,W / 2,H - 14,$impl.FontBig,"#ff6b78","center")}
       else $impl.Txt(Ctx,Msg,W / 2,H - 14,$impl.FontBig,$impl.ColText,"center");
    };
    $impl.Txt(Ctx,"Sky and clouds: NASA / KSC-08pd1628",W - 8,16,"9px ui-monospace, Consolas, monospace",$impl.Rgba(255,255,255,0.55 * SkyA),"right");
  };
  this.DrawCruise = function (Ctx, W, H, S, T) {
    var Sc = pas.TsTypes.TScenario.$new();
    var Cx = 0.0;
    var Cy = 0.0;
    var Scale = 0.0;
    var Re = 0.0;
    var Rt = 0.0;
    var F = 0.0;
    var A0 = 0.0;
    var A1 = 0.0;
    var Ang = 0.0;
    var R = 0.0;
    var X = 0.0;
    var Y = 0.0;
    var Bx = 0.0;
    var I = 0;
    Sc.$assign(pas.TsScenarios.Scenarios[S.D.Scenario]);
    Ctx.clearRect(0,0,W,H);
    F = 0;
    if (S.CruiseWeeks > 0) F = pas.TsTypes.Clamp(S.Week / S.CruiseWeeks,0,1);
    if (Sc.Id === "moon") {
      $impl.DrawBody(Ctx,"Earth",W * 0.16,H * 0.56,40);
      $impl.DrawBody(Ctx,"Moon",W * 0.84,H * 0.44,18);
      Ctx.strokeStyle = $impl.ColDim;
      Ctx.setLineDash([5,5]);
      Ctx.lineWidth = 1.4;
      Ctx.beginPath();
      Ctx.moveTo((W * 0.16) + 40,H * 0.52);
      if (S.D.Transfer === 1) {
        Bx = -H * 0.9}
       else Bx = H * 0.1;
      Ctx.quadraticCurveTo(W * 0.5,Bx,(W * 0.84) - 20,H * 0.42);
      Ctx.stroke();
      Ctx.setLineDash([]);
      X = ((1 - F) * (1 - F) * ((W * 0.16) + 40)) + (2 * (1 - F) * F * (W * 0.5)) + (F * F * ((W * 0.84) - 20));
      Y = ((1 - F) * (1 - F) * (H * 0.52)) + (2 * (1 - F) * F * Bx) + (F * F * (H * 0.42));
      $impl.DrawProbe(Ctx,X,pas.TsTypes.Clamp(Y,12,H - 12),true);
      $impl.Txt(Ctx,"EARTH TO MOON",14,H - 12,$impl.FontBig,$impl.ColText,"left");
      return;
    };
    Cx = W * 0.5;
    Cy = H * 0.52;
    Scale = (H * 0.42) / Math.max(1.0,Sc.SunAU);
    Re = Scale;
    Rt = Scale * Sc.SunAU;
    $impl.Disc(Ctx,Cx,Cy,7,"#ffd678");
    Ctx.strokeStyle = "rgba(255,255,255,0.22)";
    Ctx.lineWidth = 1;
    Ctx.beginPath();
    Ctx.arc(Cx,Cy,Re,0,2 * Math.PI);
    Ctx.stroke();
    Ctx.beginPath();
    Ctx.ellipse(Cx,Cy,Rt,Rt * 0.97,0.3,0,2 * Math.PI);
    Ctx.stroke();
    A0 = 2.4;
    A1 = A0 - (2.6 + (0.9 * Sc.Transfers[S.D.Transfer].CruiseYears));
    Ctx.strokeStyle = $impl.ColDim;
    Ctx.setLineDash([5,5]);
    Ctx.lineWidth = 1.4;
    Ctx.beginPath();
    for (I = 0; I <= 60; I++) {
      Ang = A0 + (((A1 - A0) * I) / 60);
      R = Re + ((Rt - Re) * (I / 60));
      if (I === 0) {
        Ctx.moveTo(Cx + (R * Math.cos(Ang)),Cy + (R * Math.sin(Ang)))}
       else Ctx.lineTo(Cx + (R * Math.cos(Ang)),Cy + (R * Math.sin(Ang)));
    };
    Ctx.stroke();
    Ctx.setLineDash([]);
    $impl.Disc(Ctx,Cx + (Re * Math.cos(A0 - (F * 1.4))),Cy + (Re * Math.sin(A0 - (F * 1.4))),4.5,"#5aa8ff");
    $impl.Txt(Ctx,"Earth",Cx + (Re * Math.cos(A0 - (F * 1.4))) + 8,Cy + (Re * Math.sin(A0 - (F * 1.4))) + 4,$impl.FontSmall,$impl.ColMuted,"left");
    $impl.Disc(Ctx,Cx + (Rt * Math.cos(A1)),Cy + (Rt * Math.sin(A1)),4.5,"#ffb38a");
    $impl.Txt(Ctx,Sc.Body,Cx + (Rt * Math.cos(A1)) + 8,Cy + (Rt * Math.sin(A1)) + 4,$impl.FontSmall,$impl.ColMuted,"left");
    Ang = A0 + ((A1 - A0) * F);
    R = Re + ((Rt - Re) * F);
    $impl.DrawProbe(Ctx,Cx + (R * Math.cos(Ang)),Cy + (R * Math.sin(Ang)),true);
    $impl.Txt(Ctx,"CRUISE TO " + pas.SysUtils.UpperCase(Sc.Body),14,H - 12,$impl.FontBig,$impl.ColText,"left");
    if (T < 0) return;
  };
  this.DrawChart = function (Ctx, W, H, S) {
    var X0 = 0.0;
    var Y0 = 0.0;
    var Pw = 0.0;
    var Ph = 0.0;
    var MaxV = 0.0;
    var Thr = 0.0;
    var I = 0;
    var N = 0;
    Ctx.clearRect(0,0,W,H);
    X0 = 34;
    Y0 = 22;
    Pw = W - X0 - 10;
    Ph = H - Y0 - 22;
    MaxV = 100;
    if (S.SciencePct > 100) MaxV = pas.Math.Ceil(S.SciencePct / 25) * 25;
    Ctx.lineWidth = 1;
    N = Math.round(MaxV / 25);
    for (var $l = 0, $end = N; $l <= $end; $l++) {
      I = $l;
      Ctx.strokeStyle = "rgba(255,255,255,0.08)";
      $impl.Line(Ctx,X0,Y0 + ((Ph * I) / N),X0 + Pw,Y0 + ((Ph * I) / N));
      $impl.Txt(Ctx,pas.TsFmt.FmtNum((MaxV * (N - I)) / N,0),X0 - 6,Y0 + ((Ph * I) / N) + 4,$impl.FontSmall,$impl.ColMuted,"right");
    };
    Thr = pas.TsScenarios.Scenarios[S.D.Scenario].ThresholdPct;
    Ctx.strokeStyle = "rgba(255,181,71,0.6)";
    Ctx.setLineDash([4,4]);
    $impl.Line(Ctx,X0,(Y0 + Ph) - ((Thr / MaxV) * Ph),X0 + Pw,(Y0 + Ph) - ((Thr / MaxV) * Ph));
    Ctx.setLineDash([]);
    $impl.Txt(Ctx,"minimum",(X0 + Pw) - 4,(Y0 + Ph) - ((Thr / MaxV) * Ph) - 4,$impl.FontSmall,"rgba(255,181,71,0.9)","right");
    $impl.Series(Ctx,S.HistPower,X0,Y0,Pw,Ph,100,"rgba(255,181,71,0.75)",1.2);
    $impl.Series(Ctx,S.HistData,X0,Y0,Pw,Ph,100,"rgba(74,222,128,0.75)",1.2);
    $impl.Series(Ctx,S.HistScience,X0,Y0,Pw,Ph,MaxV,$impl.ColLine,2.4);
    Ctx.fillStyle = $impl.ColLine;
    Ctx.fillRect(X0,6,14,3);
    $impl.Txt(Ctx,"science %",X0 + 19,12,$impl.FontSmall,$impl.ColText,"left");
    Ctx.fillStyle = "rgba(255,181,71,0.9)";
    Ctx.fillRect(X0 + 96,6,14,3);
    $impl.Txt(Ctx,"power %",X0 + 115,12,$impl.FontSmall,$impl.ColText,"left");
    Ctx.fillStyle = "rgba(74,222,128,0.9)";
    Ctx.fillRect(X0 + 180,6,14,3);
    $impl.Txt(Ctx,"data sent home %",X0 + 199,12,$impl.FontSmall,$impl.ColText,"left");
    $impl.Txt(Ctx,"weeks of science: " + pas.SysUtils.IntToStr(rtl.length(S.HistScience)),X0 + Pw,H - 6,$impl.FontSmall,$impl.ColMuted,"right");
  };
  this.CategoryColor = function (Cat) {
    var Result = "";
    if (Cat === "wildfires") {
      Result = "#ff8a4c"}
     else if (Cat === "severeStorms") {
      Result = "#8fb4ff"}
     else if (Cat === "floods") {
      Result = "#38d6f8"}
     else if (Cat === "seaLakeIce") {
      Result = "#ffffff"}
     else if (Cat === "volcanoes") {
      Result = "#ff4d6d"}
     else Result = "#c4a1ff";
    return Result;
  };
  this.LaunchSeconds = 15.0;
  $mod.$implcode = function () {
    $impl.ColLine = "#5ad1ff";
    $impl.ColDim = "rgba(90,209,255,0.35)";
    $impl.ColText = "#e8eef9";
    $impl.ColMuted = "#93a4c3";
    $impl.FontSmall = "11px ui-monospace, Consolas, monospace";
    $impl.FontMid = "12.5px ui-monospace, Consolas, monospace";
    $impl.FontBig = "bold 15px ui-monospace, Consolas, monospace";
    $impl.ImgSky = null;
    $impl.ImgMap = null;
    $impl.ImgCloud = rtl.arraySetLength(null,null,3);
    $impl.NewImage = function (Src) {
      var Result = null;
      Result = document.createElement("img");
      Result.src = Src;
      return Result;
    };
    $impl.Ready = function (Img) {
      var Result = false;
      Result = (Img !== null) && Img.complete && (Img.naturalWidth > 0);
      return Result;
    };
    $impl.NextRand = function (Seed) {
      var Result = 0.0;
      Seed.set(Seed.get() * 16807.0);
      Seed.set(Seed.get() - (2147483647.0 * pas.System.Trunc(Seed.get() / 2147483647.0)));
      Result = Seed.get() / 2147483647.0;
      return Result;
    };
    $impl.Rgba = function (R, G, B, A) {
      var Result = "";
      Result = "rgba(" + pas.SysUtils.IntToStr(R) + "," + pas.SysUtils.IntToStr(G) + "," + pas.SysUtils.IntToStr(B) + "," + pas.TsFmt.FmtNum(A,2) + ")";
      return Result;
    };
    $impl.Disc = function (Ctx, X, Y, R, Fill) {
      Ctx.beginPath();
      Ctx.arc(X,Y,R,0,2 * Math.PI);
      Ctx.fillStyle = Fill;
      Ctx.fill();
    };
    $impl.Line = function (Ctx, X1, Y1, X2, Y2) {
      Ctx.beginPath();
      Ctx.moveTo(X1,Y1);
      Ctx.lineTo(X2,Y2);
      Ctx.stroke();
    };
    $impl.Txt = function (Ctx, S, X, Y, Font, Color, Align) {
      Ctx.font = Font;
      Ctx.fillStyle = Color;
      Ctx.textAlign = Align;
      Ctx.fillText(S,X,Y);
    };
    $impl.Shade = function (Ctx, Cx, Cy, R) {
      var G = null;
      G = Ctx.createLinearGradient(Cx - R,0,Cx + R,0);
      G.addColorStop(0,"rgba(0,0,0,0)");
      G.addColorStop(0.5,"rgba(0,0,0,0.08)");
      G.addColorStop(1,"rgba(0,0,0,0.82)");
      Ctx.fillStyle = G;
      Ctx.fillRect(Cx - R,Cy - R,2 * R,2 * R);
    };
    $impl.Blob = function (Ctx, X, Y, Rx, Ry, Rot, Fill) {
      Ctx.beginPath();
      Ctx.ellipse(X,Y,Rx,Ry,Rot,0,2 * Math.PI);
      Ctx.fillStyle = Fill;
      Ctx.fill();
    };
    $impl.DrawBody = function (Ctx, Body, Cx, Cy, R) {
      var G = null;
      var I = 0;
      var Seed = 0.0;
      var A = 0.0;
      var Rr = 0.0;
      var X = 0.0;
      var Y = 0.0;
      Ctx.save();
      Ctx.beginPath();
      if (Body === "Apophis") {
        Seed = 99942;
        for (I = 0; I <= 11; I++) {
          A = (I / 12) * 2 * Math.PI;
          Rr = R * (0.78 + (0.3 * $impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }})));
          if (I === 0) {
            Ctx.moveTo(Cx + (Rr * Math.cos(A) * 1.25),Cy + (Rr * Math.sin(A) * 0.85))}
           else Ctx.lineTo(Cx + (Rr * Math.cos(A) * 1.25),Cy + (Rr * Math.sin(A) * 0.85));
        };
        Ctx.closePath();
      } else Ctx.arc(Cx,Cy,R,0,2 * Math.PI);
      Ctx.clip();
      G = Ctx.createRadialGradient(Cx - (R * 0.35),Cy - (R * 0.35),R * 0.1,Cx,Cy,R * 1.3);
      if (Body === "Earth") {
        G.addColorStop(0,"#8fd8ff");
        G.addColorStop(0.55,"#2f7fdc");
        G.addColorStop(1,"#0f3272");
      } else if (Body === "Moon") {
        G.addColorStop(0,"#f2f2f2");
        G.addColorStop(0.6,"#a9adb5");
        G.addColorStop(1,"#5d626c");
      } else if (Body === "Mars") {
        G.addColorStop(0,"#ffb991");
        G.addColorStop(0.55,"#d2603a");
        G.addColorStop(1,"#74290f");
      } else if (Body === "Jupiter") {
        G.addColorStop(0,"#f1dcb9");
        G.addColorStop(1,"#b98a5c");
      } else if (Body === "Europa") {
        G.addColorStop(0,"#fff7e6");
        G.addColorStop(0.6,"#d3bf9f");
        G.addColorStop(1,"#7c6649");
      } else {
        G.addColorStop(0,"#cfc5b3");
        G.addColorStop(0.6,"#857b6b");
        G.addColorStop(1,"#40392f");
      };
      Ctx.fillStyle = G;
      Ctx.fillRect(Cx - (R * 1.4),Cy - (R * 1.4),R * 2.8,R * 2.8);
      if (Body === "Earth") {
        $impl.Blob(Ctx,Cx - (R * 0.28),Cy - (R * 0.22),R * 0.34,R * 0.24,0.5,"rgba(70,150,90,0.85)");
        $impl.Blob(Ctx,Cx + (R * 0.2),Cy + (R * 0.12),R * 0.26,R * 0.4,-0.3,"rgba(84,150,84,0.85)");
        $impl.Blob(Ctx,Cx - (R * 0.15),Cy + (R * 0.5),R * 0.22,R * 0.12,0.2,"rgba(160,140,90,0.8)");
        $impl.Blob(Ctx,Cx + (R * 0.5),Cy - (R * 0.4),R * 0.2,R * 0.13,0.8,"rgba(70,150,90,0.8)");
        $impl.Blob(Ctx,Cx,Cy - (R * 0.93),R * 0.5,R * 0.12,0,"rgba(255,255,255,0.9)");
        $impl.Blob(Ctx,Cx,Cy + (R * 0.95),R * 0.55,R * 0.13,0,"rgba(255,255,255,0.9)");
        $impl.Blob(Ctx,Cx - (R * 0.1),Cy - (R * 0.02),R * 0.55,R * 0.06,-0.25,"rgba(255,255,255,0.35)");
        $impl.Blob(Ctx,Cx + (R * 0.25),Cy - (R * 0.55),R * 0.4,R * 0.05,0.3,"rgba(255,255,255,0.3)");
      } else if ((Body === "Moon") || (Body === "Apophis")) {
        Seed = 1737;
        if (Body === "Moon") {
          $impl.Blob(Ctx,Cx - (R * 0.3),Cy - (R * 0.25),R * 0.36,R * 0.26,0.4,"rgba(70,74,84,0.4)");
          $impl.Blob(Ctx,Cx + (R * 0.15),Cy + (R * 0.05),R * 0.25,R * 0.2,-0.2,"rgba(70,74,84,0.35)");
        };
        for (I = 1; I <= 16; I++) {
          X = Cx + ((($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) * 2) - 1) * R * 0.9);
          Y = Cy + ((($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) * 2) - 1) * R * 0.9);
          Rr = R * (0.03 + (0.08 * $impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }})));
          $impl.Disc(Ctx,X,Y,Rr,"rgba(40,42,50,0.35)");
          $impl.Disc(Ctx,X - (Rr * 0.2),Y - (Rr * 0.2),Rr * 0.7,"rgba(255,255,255,0.08)");
        };
      } else if (Body === "Mars") {
        $impl.Blob(Ctx,Cx - (R * 0.2),Cy + (R * 0.1),R * 0.45,R * 0.18,0.2,"rgba(96,36,18,0.45)");
        $impl.Blob(Ctx,Cx + (R * 0.35),Cy - (R * 0.25),R * 0.25,R * 0.14,-0.4,"rgba(96,36,18,0.4)");
        $impl.Blob(Ctx,Cx + (R * 0.1),Cy + (R * 0.55),R * 0.3,R * 0.1,0.1,"rgba(96,36,18,0.35)");
        $impl.Blob(Ctx,Cx,Cy - (R * 0.95),R * 0.34,R * 0.1,0,"rgba(255,255,255,0.92)");
      } else if (Body === "Jupiter") {
        for (I = -5; I <= 5; I++) if ((I % 2) === 0) {
          Ctx.fillStyle = "rgba(150,96,58,0.45)";
          Ctx.fillRect(Cx - (R * 1.4),(Cy + (I * R * 0.17)) - (R * 0.06),R * 2.8,R * 0.12);
        };
        $impl.Blob(Ctx,Cx + (R * 0.3),Cy + (R * 0.28),R * 0.2,R * 0.1,0,"rgba(190,80,50,0.75)");
      } else if (Body === "Europa") {
        Ctx.strokeStyle = "rgba(140,82,52,0.55)";
        Ctx.lineWidth = Math.max(0.8,R * 0.025);
        Seed = 1561;
        for (I = 1; I <= 9; I++) {
          Ctx.beginPath();
          Ctx.moveTo(Cx - R,Cy + ((($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) * 2) - 1) * R));
          Ctx.quadraticCurveTo(Cx + (($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) - 0.5) * R),Cy + ((($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) * 2) - 1) * R),Cx + R,Cy + ((($impl.NextRand({get: function () {
              return Seed;
            }, set: function (v) {
              Seed = v;
            }}) * 2) - 1) * R));
          Ctx.stroke();
        };
      };
      $impl.Shade(Ctx,Cx,Cy,R * 1.3);
      Ctx.restore();
      if (Body === "Earth") {
        Ctx.beginPath();
        Ctx.arc(Cx,Cy,R + 1.5,0,2 * Math.PI);
        Ctx.strokeStyle = "rgba(120,200,255,0.35)";
        Ctx.lineWidth = 2.5;
        Ctx.stroke();
      };
    };
    $impl.DrawSunHint = function (Ctx, H) {
      var I = 0;
      Ctx.strokeStyle = "rgba(255,214,120,0.5)";
      Ctx.lineWidth = 1;
      for (I = 0; I <= 4; I++) $impl.Line(Ctx,4,H * (0.26 + (I * 0.12)),22,H * (0.26 + (I * 0.12)));
      $impl.Txt(Ctx,"SUN",6,H * 0.2,$impl.FontSmall,"rgba(255,214,120,0.8)","left");
    };
    $impl.OrbitPoint = function (Nu, Rp, Ra, Inc, Omega, X, Y, Depth, Xs, Dist) {
      var A = 0.0;
      var E = 0.0;
      var R = 0.0;
      var Px = 0.0;
      var Py = 0.0;
      var Y3 = 0.0;
      var Z3 = 0.0;
      var Phi = 0.0;
      A = (Rp + Ra) / 2;
      E = 0;
      if ((Ra + Rp) > 0) E = (Ra - Rp) / (Ra + Rp);
      R = (A * (1 - (E * E))) / (1 + (E * Math.cos(Nu)));
      Px = R * Math.cos(Nu + Omega);
      Py = R * Math.sin(Nu + Omega);
      Y3 = Py * Math.cos(Inc);
      Z3 = Py * Math.sin(Inc);
      Phi = (18 * Math.PI) / 180;
      X.set(Px);
      Depth.set((Y3 * Math.cos(Phi)) + (Z3 * Math.sin(Phi)));
      Y.set(-((-Y3 * Math.sin(Phi)) + (Z3 * Math.cos(Phi))));
      Xs.set(Px);
      Dist.set(Math.sqrt((Y3 * Y3) + (Z3 * Z3)));
    };
    $impl.DrawRing = function (Ctx, Cx, Cy, Rb, Rp, Ra, Inc, Omega, Front, Color) {
      var I = 0;
      var Nu = 0.0;
      var X = 0.0;
      var Y = 0.0;
      var Dp = 0.0;
      var Xs = 0.0;
      var Ds = 0.0;
      var X2 = 0.0;
      var Y2 = 0.0;
      var Dp2 = 0.0;
      var Xs2 = 0.0;
      var Ds2 = 0.0;
      var Hidden = false;
      var Dark = false;
      Ctx.lineWidth = 1.6;
      for (I = 0; I <= 143; I++) {
        Nu = (I / 144) * 2 * Math.PI;
        $impl.OrbitPoint(Nu,Rp,Ra,Inc,Omega,{get: function () {
            return X;
          }, set: function (v) {
            X = v;
          }},{get: function () {
            return Y;
          }, set: function (v) {
            Y = v;
          }},{get: function () {
            return Dp;
          }, set: function (v) {
            Dp = v;
          }},{get: function () {
            return Xs;
          }, set: function (v) {
            Xs = v;
          }},{get: function () {
            return Ds;
          }, set: function (v) {
            Ds = v;
          }});
        $impl.OrbitPoint(((I + 1) / 144) * 2 * Math.PI,Rp,Ra,Inc,Omega,{get: function () {
            return X2;
          }, set: function (v) {
            X2 = v;
          }},{get: function () {
            return Y2;
          }, set: function (v) {
            Y2 = v;
          }},{get: function () {
            return Dp2;
          }, set: function (v) {
            Dp2 = v;
          }},{get: function () {
            return Xs2;
          }, set: function (v) {
            Xs2 = v;
          }},{get: function () {
            return Ds2;
          }, set: function (v) {
            Ds2 = v;
          }});
        if ((Dp <= 0) !== Front) continue;
        Hidden = (Dp > 0) && (Math.sqrt((X * X) + (Y * Y)) < Rb);
        if (Hidden) continue;
        Dark = (Xs > 0) && (Ds < Rb);
        if (Dark) {
          Ctx.strokeStyle = "rgba(120,130,160,0.55)"}
         else if (Front) {
          Ctx.strokeStyle = Color}
         else Ctx.strokeStyle = $impl.ColDim;
        $impl.Line(Ctx,Cx + X,Cy + Y,Cx + X2,Cy + Y2);
      };
    };
    $impl.DrawProbe = function (Ctx, X, Y, Lit) {
      if (Lit) {
        Ctx.fillStyle = "#ffffff"}
       else Ctx.fillStyle = "#7f8aa6";
      Ctx.fillRect(X - 2.5,Y - 2.5,5,5);
      Ctx.fillStyle = $impl.ColLine;
      Ctx.fillRect(X - 8,Y - 1,5,2);
      Ctx.fillRect(X + 3,Y - 1,5,2);
    };
    $impl.ScaleAlt = function (AltKm, BodyKm) {
      var Result = 0.0;
      Result = 1.28 + (1.25 * Math.log10(1 + ((1.2 * AltKm) / BodyKm)));
      return Result;
    };
    $impl.InstrCode = function (Id) {
      var Result = "";
      if (Id === "cam_ctx") {
        Result = "CAM"}
       else if (Id === "cam_hires") {
        Result = "TELE"}
       else if (Id === "spec_vnir") {
        Result = "SPEC"}
       else if (Id === "tir") {
        Result = "TIR"}
       else if (Id === "sar") {
        Result = "RADAR"}
       else if (Id === "lidar") {
        Result = "LIDAR"}
       else if (Id === "neutron") {
        Result = "NEUT"}
       else if (Id === "mag") {
        Result = "MAG"}
       else if (Id === "plasma") {
        Result = "PLAS"}
       else if (Id === "massspec") {
        Result = "MASS"}
       else if (Id === "radiometer") {
        Result = "MWR"}
       else if (Id === "uvs") {
        Result = "UV"}
       else if (Id === "dust") {
        Result = "DUST"}
       else if (Id === "radio") {
        Result = "RSCI"}
       else if (Id === "relay") {
        Result = "RELAY"}
       else Result = "?";
      return Result;
    };
    $impl.DrawRocket = function (Ctx, X, Y, Hgt, Wid, Size, Boosters, Fire) {
      var G = null;
      var K = 0;
      var Bx = 0.0;
      var Fl = 0.0;
      if (Fire > 0) {
        Fl = Hgt * (0.55 + (0.25 * Fire));
        G = Ctx.createLinearGradient(0,Y,0,Y + Fl);
        G.addColorStop(0,"rgba(255,255,255,0.95)");
        G.addColorStop(0.25,"rgba(255,220,120,0.9)");
        G.addColorStop(0.6,"rgba(255,130,50,0.5)");
        G.addColorStop(1,"rgba(255,90,30,0)");
        Ctx.fillStyle = G;
        Ctx.beginPath();
        Ctx.moveTo(X - (Wid * 0.5),Y);
        Ctx.quadraticCurveTo(X - (Wid * 1.3),Y + (Fl * 0.5),X,Y + Fl);
        Ctx.quadraticCurveTo(X + (Wid * 1.3),Y + (Fl * 0.5),X + (Wid * 0.5),Y);
        Ctx.closePath();
        Ctx.fill();
      };
      if (Boosters) for (K = 0; K <= 1; K++) {
        if (K === 0) {
          Bx = X - (Wid * 1.05)}
         else Bx = X + (Wid * 1.05);
        Ctx.fillStyle = "#d9dee8";
        Ctx.fillRect(Bx - (Wid * 0.42),Y - (Hgt * 0.62),Wid * 0.84,Hgt * 0.62);
        Ctx.beginPath();
        Ctx.moveTo(Bx - (Wid * 0.42),Y - (Hgt * 0.62));
        Ctx.quadraticCurveTo(Bx,Y - (Hgt * 0.78),Bx + (Wid * 0.42),Y - (Hgt * 0.62));
        Ctx.closePath();
        Ctx.fill();
        Ctx.fillStyle = "#2b3243";
        Ctx.fillRect(Bx - (Wid * 0.3),Y,Wid * 0.6,Hgt * 0.035);
      };
      Ctx.fillStyle = "#eef2f8";
      Ctx.fillRect(X - (Wid / 2),Y - (Hgt * 0.86),Wid,Hgt * 0.86);
      Ctx.beginPath();
      Ctx.moveTo(X - (Wid * 0.6),Y - (Hgt * 0.84));
      Ctx.lineTo(X - (Wid * 0.6),Y - (Hgt * 0.92));
      Ctx.quadraticCurveTo(X - (Wid * 0.5),Y - Hgt,X,Y - (Hgt * 1.03));
      Ctx.quadraticCurveTo(X + (Wid * 0.5),Y - Hgt,X + (Wid * 0.6),Y - (Hgt * 0.92));
      Ctx.lineTo(X + (Wid * 0.6),Y - (Hgt * 0.84));
      Ctx.closePath();
      Ctx.fill();
      Ctx.fillStyle = "#2b3243";
      Ctx.fillRect(X - (Wid / 2),Y - (Hgt * 0.52),Wid,Hgt * 0.03);
      Ctx.fillRect(X - (Wid / 2),Y - (Hgt * 0.84),Wid,Hgt * 0.012);
      var $tmp = Size;
      if ($tmp === 0) {
        Ctx.fillStyle = "#1c2333"}
       else if ($tmp === 1) {
        Ctx.fillStyle = "#e2572f"}
       else if ($tmp === 2) {
        Ctx.fillStyle = "#5ad1ff"}
       else {
        Ctx.fillStyle = "#ffb547";
      };
      Ctx.fillRect(X - (Wid / 2),Y - (Hgt * 0.32),Wid,Hgt * 0.05);
      Ctx.fillStyle = "#aab3c4";
      Ctx.beginPath();
      Ctx.moveTo(X - (Wid / 2),Y - (Hgt * 0.1));
      Ctx.lineTo(X - (Wid * 0.95),Y);
      Ctx.lineTo(X - (Wid / 2),Y);
      Ctx.closePath();
      Ctx.fill();
      Ctx.beginPath();
      Ctx.moveTo(X + (Wid / 2),Y - (Hgt * 0.1));
      Ctx.lineTo(X + (Wid * 0.95),Y);
      Ctx.lineTo(X + (Wid / 2),Y);
      Ctx.closePath();
      Ctx.fill();
      Ctx.fillStyle = "#2b3243";
      Ctx.fillRect(X - (Wid * 0.34),Y,Wid * 0.68,Hgt * 0.035);
      G = Ctx.createLinearGradient(X - (Wid / 2),0,X + (Wid / 2),0);
      G.addColorStop(0,"rgba(0,0,0,0)");
      G.addColorStop(1,"rgba(0,0,0,0.3)");
      Ctx.fillStyle = G;
      Ctx.fillRect(X - (Wid / 2),Y - (Hgt * 0.86),Wid,Hgt * 0.86);
    };
    $impl.Series = function (Ctx, V, X0, Y0, Pw, Ph, MaxV, Color, Wd) {
      var I = 0;
      var N = 0;
      N = rtl.length(V);
      if (N < 2) return;
      Ctx.strokeStyle = Color;
      Ctx.lineWidth = Wd;
      Ctx.beginPath();
      for (var $l = 0, $end = N - 1; $l <= $end; $l++) {
        I = $l;
        if (I === 0) {
          Ctx.moveTo(X0,(Y0 + Ph) - (pas.TsTypes.Clamp(V[I] / MaxV,0,1) * Ph))}
         else Ctx.lineTo(X0 + ((Pw * I) / (N - 1)),(Y0 + Ph) - (pas.TsTypes.Clamp(V[I] / MaxV,0,1) * Ph));
      };
      Ctx.stroke();
    };
  };
},["TsCatalog","TsScenarios","TsEngine","TsFmt"]);
rtl.module("strutils",["System","SysUtils"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.IfThen = function (AValue, ATrue, AFalse) {
    var Result = "";
    if (AValue) {
      Result = ATrue}
     else Result = AFalse;
    return Result;
  };
  this.Soundex = function (AText, ALength) {
    var Result = "";
    var S = "\x00";
    var PS = "\x00";
    var I = 0;
    var L = 0;
    Result = "";
    PS = "\x00";
    if (AText.length > 0) {
      Result = pas.System.upcase(AText.charAt(0));
      I = 2;
      L = AText.length;
      while ((I <= L) && (Result.length < ALength)) {
        S = $impl.SScore.charAt(AText.charCodeAt(I - 1) - 1);
        if (!(S.charCodeAt() in rtl.createSet(48,105,PS.charCodeAt()))) Result = Result + S;
        if (S !== "i") PS = S;
        I += 1;
      };
    };
    L = Result.length;
    if (L < ALength) Result = Result + pas.System.StringOfChar("0",ALength - L);
    return Result;
  };
  this.SoundexSimilar = function (AText, AOther, ALength) {
    var Result = false;
    Result = $mod.Soundex(AText,ALength) === $mod.Soundex(AOther,ALength);
    return Result;
  };
  this.SoundexSimilar$1 = function (AText, AOther) {
    var Result = false;
    Result = $mod.SoundexSimilar(AText,AOther,4);
    return Result;
  };
  this.SoundexProc = function (AText, AOther) {
    var Result = false;
    Result = $mod.SoundexSimilar$1(AText,AOther);
    return Result;
  };
  this.AnsiResemblesProc = null;
  this.ResemblesProc = null;
  $mod.$implcode = function () {
    $impl.SScore = "00000000000000000000000000000000" + "00000000000000000000000000000000" + "0123012i02245501262301i2i2" + "000000" + "0123012i02245501262301i2i2" + "00000000000000000000000000000000" + "00000000000000000000000000000000" + "00000000000000000000000000000000" + "00000000000000000000000000000000" + "00000";
  };
  $mod.$init = function () {
    $mod.AnsiResemblesProc = $mod.SoundexProc;
    $mod.ResemblesProc = $mod.SoundexProc;
  };
},["JS"]);
rtl.module("WebViews",["System","SysUtils","Math","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.ViewTitle = function () {
    var Result = "";
    var Live = "";
    if (pas.WebNasa.NasaStatus.EonetLive) {
      Live = "live today"}
     else if (pas.WebNasa.NasaStatus.SnapshotDate !== "") {
      Live = "as of " + pas.TsFmt.NiceDate(pas.WebNasa.NasaStatus.SnapshotDate)}
     else Live = "loading";
    Result = $impl.TopBar(-1) + '<main class="hero">' + '<h1 class="hero-mark">TRADE<span>SPACE</span></h1>' + '<p class="hero-tag">' + pas.TsTypes.GameTagline + "</p>" + '<p class="hero-sub">Build a whole space mission, from the science question to the last day of operations. ' + "Every gram, watt and dollar you spend on one thing is taken from another. For one to four players.</p>" + '<div class="hero-actions">' + pas.WebUtil.Btn("btn btn-primary btn-big","start","",pas.WebUtil.IconLg("rocket") + "Start a mission") + pas.WebUtil.Btn("btn btn-big","log","",pas.WebUtil.IconLg("trophy") + "Mission log") + pas.WebUtil.Btn("btn btn-big","help","",pas.WebUtil.IconLg("info") + "How to play") + "</div>" + '<div class="loop-strip">' + '<div class="loop-step"><b>1. Take the mission</b><span>Five real destinations, from Earth orbit to Europa.</span></div>' + '<div class="loop-step"><b>2. Design the spacecraft</b><span>Orbit, instruments, power, radio, rocket, budget.</span></div>' + '<div class="loop-step"><b>3. Face the review board</b><span>It tells you what will fail, and why.</span></div>' + '<div class="loop-step"><b>4. Fly it</b><span>Launch, operate, decide, and read the report.</span></div>' + "</div>" + '<div class="data-strip">' + '<div class="ds-item"><div class="ds-num">' + pas.SysUtils.IntToStr(pas.WebNasa.NasaStatus.EonetCount) + "</div>" + "<p>real natural events on Earth (" + Live + ", NASA EONET). They are your targets in Disaster Watch.</p></div>" + '<div class="ds-item"><div class="ds-num">' + pas.SysUtils.IntToStr(rtl.length(pas.TsScenarios.SpaceWeather)) + "</div>" + "<p>real solar storms from NASA's DONKI database. They strike your spacecraft in flight.</p></div>" + '<div class="ds-item"><div class="ds-num">' + pas.SysUtils.IntToStr(pas.WebNasa.NasaStatus.ApophisDays) + " days</div>" + "<p>until asteroid Apophis skims past Earth (NASA JPL). That is your real deadline in Race to Apophis.</p></div>" + "</div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewSetup = function () {
    var Result = "";
    var I = 0;
    var Sc = pas.TsTypes.TScenario.$new();
    var Cls = "";
    var Txt = "";
    var Df = 0;
    Result = $impl.TopBar(0) + '<main class="wrap">';
    Result = Result + '<div class="section-head"><span class="step">1</span><h2>Choose a mission</h2></div><div class="scen-grid">';
    for (var $l = 0, $end = rtl.length(pas.TsScenarios.Scenarios) - 1; $l <= $end; $l++) {
      I = $l;
      Sc.$assign(pas.TsScenarios.Scenarios[I]);
      Cls = "scen-card";
      if (I === pas.WebState.Scen) Cls = Cls + " sel";
      Result = Result + '<button type="button" class="' + Cls + '" data-act="scen" data-a="' + pas.SysUtils.IntToStr(I) + '">' + '<div class="scen-top"><div class="planet planet-' + pas.SysUtils.LowerCase(Sc.Body) + '"></div><div><h3>' + Sc.Name + '</h3><span class="muted small">' + Sc.Body + "</span></div></div>" + '<p class="small">' + Sc.Tagline + "</p>" + '<div class="kv"><span class="muted">Level</span>' + $impl.Dots(Sc.Level) + "</div>" + $impl.KV("Cost cap",pas.TsFmt.FmtMoney(Sc.CostCapM * pas.TsEngine.DifficultyCapMult(pas.WebState.Difficulty)));
      if (Sc.UsesEonet || Sc.UsesApophis) Result = Result + "<div>" + pas.WebUtil.Chip("chip-real","Driven by live NASA data") + "</div>";
      Result = Result + "</button>";
    };
    Result = Result + "</div>";
    Result = Result + '<div class="section-head"><span class="step">2</span><h2>Choose the challenge</h2></div>' + '<div class="panel"><div class="row"><div class="seg" role="group" aria-label="Difficulty">';
    for (Df = 0; Df <= 2; Df++) {
      Cls = "seg-btn";
      if (Df === pas.WebState.Difficulty) Cls = Cls + " on";
      Result = Result + pas.WebUtil.Btn(Cls,"diff",pas.SysUtils.IntToStr(Df),pas.TsTypes.DifficultyName[Df]);
    };
    Result = Result + "</div>";
    var $tmp = pas.WebState.Difficulty;
    if ($tmp === 0) {
      Txt = "A bigger budget, a rocket that cannot fail and fewer surprises. Best for a first flight."}
     else if ($tmp === 2) {
      Txt = "A tighter budget, more mass growth and more things going wrong. For crews who have flown before."}
     else {
      Txt = "Real budgets, real odds. Rockets can fail and hardware breaks at the rate your design earns.";
    };
    Result = Result + '<span class="muted">' + Txt + "</span></div>" + '<p style="margin-top:12px"><label class="toggle"><input type="checkbox" data-in="sandbox"';
    if (pas.WebState.Sandbox) Result = Result + " checked";
    Result = Result + '> <span><b>Sandbox</b> <span class="muted">: no cost cap, to experiment freely. Physics still applies.</span></span></label></p></div>';
    Result = Result + '<div class="section-head"><span class="step">3</span><h2>Choose your crew</h2>' + '<span class="muted">One screen, one to four players. Each player owns part of the design and has a goal of their own.</span></div>' + '<div class="panel"><div class="row" style="margin-bottom:12px"><div class="seg" role="group" aria-label="Number of players">';
    for (I = 1; I <= 4; I++) {
      Cls = "seg-btn";
      if (I === pas.WebState.Players) Cls = Cls + " on";
      if (I === 1) {
        Result = Result + pas.WebUtil.Btn(Cls,"players","1","1 player")}
       else Result = Result + pas.WebUtil.Btn(Cls,"players",pas.SysUtils.IntToStr(I),pas.SysUtils.IntToStr(I) + " players");
    };
    Result = Result + '</div></div><div class="crew-grid">';
    for (var $l1 = 0, $end1 = pas.WebState.Players - 1; $l1 <= $end1; $l1++) {
      I = $l1;
      Result = Result + '<div class="crew-row"><input type="text" maxlength="18" aria-label="Name of player ' + pas.SysUtils.IntToStr(I + 1) + '" data-in="pname" data-a="' + pas.SysUtils.IntToStr(I) + '" value="' + pas.WebUtil.Esc(pas.WebState.PlayerName[I]) + '">' + '<span class="small">' + pas.WebState.PlayerRoles(I) + "</span></div>";
    };
    Result = Result + "</div></div>";
    Result = Result + '<div class="row" style="margin-top:22px">' + pas.WebUtil.Btn("btn btn-primary btn-big","brief","","Read the briefing " + pas.WebUtil.Icon("next")) + "</div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewBrief = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var I = 0;
    var R = 0;
    var Sun = 0.0;
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Sun = 1 / (Sc.SunAU * Sc.SunAU);
    Result = $impl.TopBar(0) + '<main class="wrap">' + '<div class="row"><div class="planet planet-' + pas.SysUtils.LowerCase(Sc.Body) + '"></div><div><h4>Announcement of opportunity</h4>' + "<h2>" + Sc.Name + ": " + Sc.Tagline + "</h2></div></div>" + '<div class="brief-grid" style="margin-top:16px"><div>' + '<div class="panel"><p class="lead">' + Sc.Brief + "</p>" + '<div class="finding f-info" style="margin-top:14px"><div class="finding-title">' + pas.WebUtil.Icon("target") + "Your objective</div><p>" + Sc.Objective + '</p></div><div class="fact-row">' + $impl.Fact(pas.TsFmt.FmtMoney(Sc.CostCapM * pas.TsEngine.DifficultyCapMult(pas.WebState.Difficulty)),"cost cap for everything: spacecraft, rocket, operations") + $impl.Fact($impl.DeadlineText(Sc),"so a slow, complicated design may be too late") + $impl.Fact(pas.TsFmt.FmtPct(Sun),"of the sunlight Earth gets") + $impl.Fact(pas.TsFmt.FmtYears(Sc.MinLife),"of science operations, at least");
    if (Sc.NearEarth) {
      Result = Result + $impl.Fact("0.01 s","for a radio signal to reach the ground")}
     else Result = Result + $impl.Fact(pas.TsFmt.FmtNum((((Sc.EarthMinAU + Sc.EarthMaxAU) / 2) * 499) / 60,1) + " min","for a radio signal to reach Earth, on average");
    if (Sc.UsesApophis) Result = Result + $impl.Fact(pas.SysUtils.IntToStr(Math.round(pas.TsScenarios.ApophisDays)) + " days","until the real flyby on " + pas.TsFmt.NiceDate(pas.TsScenarios.ApophisDate)) + $impl.Fact(pas.TsFmt.FmtNum(pas.TsScenarios.ApophisMissKm,0) + " km","closest distance from Earth's centre (NASA NeoWs)");
    Result = Result + "</div></div>";
    if (Sc.UsesEonet) Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("globe") + "<h3>Your targets: real events happening now</h3>" + pas.WebUtil.Chip("chip-real",pas.TsScenarios.EarthEventsSource) + '</div><div class="map-box"><canvas id="cv-map" width="1280" height="640" ' + 'role="img" aria-label="World map showing real natural events from NASA EONET"></canvas></div>' + $impl.EventLegend() + '<p class="small muted" style="margin-top:8px">Each dot is a real wildfire, storm, flood or ice event listed by NASA\'s Earth Observatory ' + "Natural Event Tracker. Where they are decides which orbit works, and what kind they are decides which instruments matter. " + "Map: NASA Blue Marble.</p></div>";
    Result = Result + '</div><div><div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("flask") + "<h3>What the science team wants</h3></div>" + $impl.PriorityBars(false);
    if (Sc.UsesEonet) Result = Result + '<p class="small muted" style="margin-top:8px">These priorities were worked out from today\'s real events.</p>';
    Result = Result + '</div><div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("info") + "<h3>Worth knowing</h3></div>";
    for (var $l = 0, $end = Math.min(3,rtl.length(Sc.Facts) - 1); $l <= $end; $l++) {
      I = $l;
      Result = Result + '<p class="small" style="margin-top:6px">' + Sc.Facts[I] + "</p>";
    };
    Result = Result + "</div></div></div>";
    if (pas.WebState.Players > 1) {
      Result = Result + '<div class="section-head"><h2>Your crew</h2><span class="muted">Everyone scores together, but each role also has a goal of its own. They pull in different directions. That is the point.</span></div><div class="role-cards">';
      for (R = 0; R <= 3; R++) Result = Result + '<div class="role-card role-' + pas.WebState.RoleClass(R) + '"><h4>' + pas.TsTypes.RoleName[R] + "</h4><h3>" + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(R)) + '</h3><p class="small" style="margin-top:6px">' + pas.TsScore.RoleGoalText(R) + "</p></div>";
      Result = Result + "</div>";
    };
    Result = Result + '<div class="section-head"><h2>Real missions like this one</h2><span class="muted">At the end, your design is compared with them.</span></div><div class="analog-grid">';
    for (var $l1 = 0, $end1 = rtl.length(Sc.Analogs) - 1; $l1 <= $end1; $l1++) {
      I = $l1;
      Result = Result + '<div class="analog"><h3>' + Sc.Analogs[I].Name + '</h3><span class="muted tiny">' + Sc.Analogs[I].Agency + ", " + Sc.Analogs[I].Year + '</span><p style="margin:6px 0">' + Sc.Analogs[I].Blurb + '</p><div class="stats">' + $impl.Stat("mass",pas.TsFmt.FmtMass(Sc.Analogs[I].MassKg)) + $impl.Stat("cost","~" + pas.TsFmt.FmtMoney(Sc.Analogs[I].CostM)) + '</div><p style="margin-top:6px">' + pas.WebUtil.Link(Sc.Analogs[I].Url,"Mission page") + "</p></div>";
    };
    Result = Result + '</div><div class="row" style="margin-top:22px">' + pas.WebUtil.Btn("btn","start","",pas.WebUtil.Icon("back") + "Change mission") + pas.WebUtil.Btn("btn btn-primary btn-big","lab","","Open the design lab " + pas.WebUtil.Icon("next")) + "</div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewLab = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = $impl.TopBar(1) + '<main class="wrap"><div class="row" style="margin-bottom:14px"><div class="planet planet-' + pas.SysUtils.LowerCase(Sc.Body) + '" style="width:34px;height:34px"></div><div><h4>Design lab</h4><h2>' + Sc.Name + '</h2></div><span class="spacer"></span>' + pas.WebUtil.Chip("",pas.TsTypes.DifficultyName[pas.WebState.Difficulty]);
    if (pas.WebState.Sandbox) Result = Result + pas.WebUtil.Chip("chip-info","Sandbox");
    Result = Result + pas.WebUtil.Btn("btn btn-ghost btn-small","brief","","Briefing") + "</div>";
    if (pas.WebState.SharedNote !== "") Result = Result + '<div class="finding f-info" style="margin-bottom:14px"><div class="finding-title">' + pas.WebUtil.Icon("share") + "<span>" + pas.WebUtil.Esc(pas.WebState.SharedNote) + "</span></div></div>";
    Result = Result + '<div class="lab"><nav class="lab-nav" id="lab-nav" aria-label="Design steps">' + $mod.ViewLabNav() + "</nav>" + '<section class="lab-main" id="lab-main">' + $mod.ViewLabMain() + "</section>" + '<aside class="lab-dash" id="lab-dash" aria-label="Mission resources">' + $mod.ViewLabDash() + "</aside></div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewLabNav = function () {
    var Result = "";
    var I = 0;
    var Cls = "";
    Result = "";
    for (I = 0; I <= 6; I++) {
      Cls = "tab";
      if (I === pas.WebState.LabTab) Cls = Cls + " on";
      Result = Result + '<button type="button" class="' + Cls + '" data-act="tab" data-a="' + pas.SysUtils.IntToStr(I) + '">' + '<span class="tab-n">' + pas.SysUtils.IntToStr(I + 1) + "</span>" + pas.WebUtil.Icon(pas.WebState.TabIcon[I]) + '<span class="tab-label">' + pas.WebState.TabName[I] + "</span>";
      if (pas.WebState.Players > 1) Result = Result + pas.WebUtil.Chip("chip-" + pas.WebState.RoleClass(pas.WebState.TabRole[I]),pas.TsTypes.RoleShort[pas.WebState.TabRole[I]]);
      Result = Result + $impl.TabDot(I) + "</button>";
    };
    Result = Result + '<div style="height:6px"></div>';
    if (pas.WebState.A.Blockers > 0) {
      Result = Result + pas.WebUtil.Btn("btn btn-primary","review","",pas.WebUtil.Icon("flag") + "Review board (" + pas.SysUtils.IntToStr(pas.WebState.A.Blockers) + " to fix)")}
     else Result = Result + pas.WebUtil.Btn("btn btn-primary","review","",pas.WebUtil.Icon("flag") + "Go to the review board");
    Result = Result + pas.WebUtil.Btn("btn btn-ghost btn-small","example","","Load an example design") + pas.WebUtil.Btn("btn btn-ghost btn-small","share","",pas.WebUtil.Icon("share") + "Share this design");
    return Result;
  };
  this.ViewLabMain = function () {
    var Result = "";
    var $tmp = pas.WebState.LabTab;
    if ($tmp === 0) {
      Result = $impl.TabOrbit()}
     else if ($tmp === 1) {
      Result = $impl.TabPayload()}
     else if ($tmp === 2) {
      Result = $impl.TabSpacecraft()}
     else if ($tmp === 3) {
      Result = $impl.TabPower()}
     else if ($tmp === 4) {
      Result = $impl.TabComms()}
     else if ($tmp === 5) {
      Result = $impl.TabLaunch()}
     else {
      Result = $impl.TabPlan();
    };
    return Result;
  };
  this.ViewLabDash = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var Tone = "";
    var V = "";
    var Dl = "";
    var I = 0;
    var Shown = 0;
    var Sev = 0;
    var R = 0;
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("target") + "<h3>Mission resources</h3></div>";
    Tone = "good";
    if (pas.WebState.A.CostTotal > pas.WebState.A.CapM) {
      Tone = "bad";
      if (pas.WebState.D.Sandbox) Tone = "info";
    } else if (pas.WebState.A.CostMargin < 0.05) Tone = "warn";
    Dl = $impl.Delta(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal,$impl.Signed(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal,pas.TsFmt.FmtMoney(Math.abs(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal))),true);
    Result = Result + $impl.Gauge("cost","coin","Cost",pas.TsFmt.FmtMoney(pas.WebState.A.CostTotal) + " of " + pas.TsFmt.FmtMoney(pas.WebState.A.CapM),pas.WebState.A.CostTotal / pas.WebState.A.CapM,Tone,-1,Dl);
    if (pas.WebState.D.Launcher < 0) {
      Result = Result + $impl.Gauge("mass","mass","Launch mass",pas.TsFmt.FmtMass(pas.WebState.A.WetKg) + ", no rocket",0,"bad",-1,"")}
     else {
      Tone = "good";
      if ((pas.WebState.A.LvCapKg <= 0) || (pas.WebState.A.WetKg > pas.WebState.A.LvCapKg)) {
        Tone = "bad"}
       else if (pas.WebState.A.MassMargin < 0.1) Tone = "warn";
      V = pas.TsFmt.FmtMass(pas.WebState.A.WetKg) + " of " + pas.TsFmt.FmtMass(pas.WebState.A.LvCapKg);
      Dl = $impl.Delta(pas.WebState.A.WetKg - pas.WebState.PrevA.WetKg,$impl.Signed(pas.WebState.A.WetKg - pas.WebState.PrevA.WetKg,pas.TsFmt.FmtMass(Math.abs(pas.WebState.A.WetKg - pas.WebState.PrevA.WetKg))),true);
      if (pas.WebState.A.LvCapKg > 0) {
        Result = Result + $impl.Gauge("mass","mass","Launch mass",V,pas.WebState.A.WetKg / pas.WebState.A.LvCapKg,Tone,-1,Dl)}
       else Result = Result + $impl.Gauge("mass","mass","Launch mass",pas.TsFmt.FmtMass(pas.WebState.A.WetKg) + ", cannot get there",1,"bad",-1,Dl);
    };
    Tone = "good";
    if (pas.WebState.A.GenAvgW < pas.WebState.A.LoadAvgW) {
      Tone = "bad"}
     else if (pas.WebState.A.PowerMargin < 0.2) Tone = "warn";
    Dl = $impl.Delta(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW,$impl.Signed(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW,pas.TsFmt.FmtPower(Math.abs(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW))),true);
    if (pas.WebState.A.GenAvgW > 0) {
      Result = Result + $impl.Gauge("power","bolt","Power",pas.TsFmt.FmtPower(pas.WebState.A.LoadAvgW) + " of " + pas.TsFmt.FmtPower(pas.WebState.A.GenAvgW),pas.WebState.A.LoadAvgW / pas.WebState.A.GenAvgW,Tone,-1,Dl)}
     else Result = Result + $impl.Gauge("power","bolt","Power",pas.TsFmt.FmtPower(pas.WebState.A.LoadAvgW) + " needed, none made",1,"bad",-1,Dl);
    Tone = "good";
    if (pas.WebState.A.DataReturn < 0.3) {
      Tone = "bad"}
     else if (pas.WebState.A.DataReturn < 0.8) Tone = "warn";
    Dl = $impl.Delta(pas.WebState.A.DataReturn - pas.WebState.PrevA.DataReturn,pas.TsFmt.FmtSignedPct(pas.WebState.A.DataReturn - pas.WebState.PrevA.DataReturn),false);
    Result = Result + $impl.Gauge("data","data","Data sent home",pas.TsFmt.FmtPct(pas.WebState.A.DataReturn) + " of " + pas.TsFmt.FmtData(pas.WebState.A.GenGbitDay) + "/day",pas.WebState.A.DataReturn,Tone,-1,Dl);
    Tone = "good";
    if (pas.WebState.A.SciencePct < Sc.ThresholdPct) {
      Tone = "bad"}
     else if (pas.WebState.A.SciencePct < 85) Tone = "warn";
    Dl = $impl.Delta(pas.WebState.A.SciencePct - pas.WebState.PrevA.SciencePct,$impl.Signed(pas.WebState.A.SciencePct - pas.WebState.PrevA.SciencePct,pas.TsFmt.FmtNum(Math.abs(pas.WebState.A.SciencePct - pas.WebState.PrevA.SciencePct),0)),false);
    Result = Result + $impl.Gauge("science","flask","Predicted science",pas.TsFmt.FmtNum(pas.WebState.A.SciencePct,0) + " % of the goal",pas.WebState.A.SciencePct / 120,Tone,Sc.ThresholdPct / 120,Dl);
    Tone = "good";
    if (pas.WebState.A.MissedDeadline) Tone = "warn";
    Dl = $impl.Delta(pas.WebState.A.DevYears - pas.WebState.PrevA.DevYears,$impl.Signed(pas.WebState.A.DevYears - pas.WebState.PrevA.DevYears,pas.TsFmt.FmtNum(Math.abs(pas.WebState.A.DevYears - pas.WebState.PrevA.DevYears),1)) + " y",true);
    if (Sc.ArriveBy) {
      Result = Result + $impl.Gauge("time","clock","Arrival",pas.TsFmt.FmtYears(pas.WebState.A.ArriveYear) + ", due in " + pas.TsFmt.FmtYears(Sc.DeadlineYears),pas.WebState.A.ArriveYear / Sc.DeadlineYears,Tone,-1,Dl)}
     else Result = Result + $impl.Gauge("time","clock","Ready to launch",pas.TsFmt.FmtYears(pas.WebState.A.LaunchYear) + ", due in " + pas.TsFmt.FmtYears(Sc.DeadlineYears),pas.WebState.A.LaunchYear / Sc.DeadlineYears,Tone,-1,Dl);
    Tone = "good";
    if (pas.WebState.A.SuccessProb < 0.6) {
      Tone = "bad"}
     else if (pas.WebState.A.SuccessProb < 0.8) Tone = "warn";
    Result = Result + $impl.Gauge("risk","shield","Chance of finishing",pas.TsFmt.FmtPct(pas.WebState.A.SuccessProb),pas.WebState.A.SuccessProb,Tone,-1,"");
    Result = Result + '<p class="tiny muted" style="margin-top:8px">Click any gauge to see what is inside it.</p></div>';
    Result = Result + $impl.RippleText();
    Result = Result + '<div class="cv-box"><canvas id="cv-craft" width="680" height="460" role="img" aria-label="Blueprint of your spacecraft"></canvas>' + '<div class="cv-cap">Your spacecraft, drawn from the design. Purple boxes are instruments.</div></div>';
    if (pas.WebState.Players > 1) {
      Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("users") + "<h3>Crew goals</h3></div>";
      for (R = 0; R <= 3; R++) {
        Result = Result + '<div class="row small" style="margin:5px 0;flex-wrap:nowrap;align-items:flex-start">';
        if (pas.TsScore.RoleForecast(R,pas.WebState.A,pas.WebState.D)) {
          Result = Result + pas.WebUtil.Chip("chip-good",pas.WebUtil.Icon("check"))}
         else Result = Result + pas.WebUtil.Chip("chip-bad",pas.WebUtil.Icon("x"));
        Result = Result + "<span><b>" + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(R)) + '</b> <span class="muted">(' + pas.TsTypes.RoleShort[R] + ")</span>: " + pas.TsScore.RoleGoalText(R) + "</span></div>";
      };
      Result = Result + "</div>";
    };
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("flag") + "<h3>What the review board will say</h3></div>";
    Shown = 0;
    for (var $l = 3; $l >= 2; $l--) {
      Sev = $l;
      for (var $l1 = 0, $end = rtl.length(pas.WebState.A.Findings) - 1; $l1 <= $end; $l1++) {
        I = $l1;
        if ((pas.WebState.A.Findings[I].Sev === Sev) && (Shown < 3)) {
          Result = Result + '<div class="finding ' + $impl.SevClass(Sev) + '"><div class="finding-title"><span>' + pas.WebState.A.Findings[I].Title + '</span></div><p class="fix">' + pas.WebState.TabName[pas.WebState.FindingTab(pas.WebState.A.Findings[I].Code)] + " tab</p></div>";
          Shown += 1;
        };
      };
    };
    if (Shown === 0) {
      Result = Result + '<div class="finding f-good"><div class="finding-title">' + pas.WebUtil.Icon("check") + "<span>The design closes</span></div>" + "<p>Mass, power, data, money and time all balance.</p></div>"}
     else if ((pas.WebState.A.Blockers + pas.WebState.A.Warnings) > Shown) Result = Result + '<p class="small muted" style="margin-top:8px">and ' + pas.SysUtils.IntToStr((pas.WebState.A.Blockers + pas.WebState.A.Warnings) - Shown) + " more.</p>";
    Result = Result + "</div>";
    return Result;
  };
  this.PowerInfo = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var I = 0;
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    O.$assign(Sc.Orbits[pas.WebState.D.Orbit]);
    Result = '<div class="numgrid">' + $impl.Num(pas.TsFmt.FmtPct(1 / (Sc.SunAU * Sc.SunAU)),"of Earth's sunlight") + $impl.Num(pas.TsFmt.FmtPower(250 / (Sc.SunAU * Sc.SunAU)),"from each square metre") + $impl.Num(pas.TsFmt.FmtPct(O.EclipseFrac),"of each orbit in shadow") + $impl.Num(pas.TsFmt.FmtNum(O.MaxEclipseHr,1) + " h","longest night") + $impl.Num(pas.TsFmt.FmtPower(pas.WebState.A.GenAvgW),"made, averaged over an orbit") + $impl.Num(pas.TsFmt.FmtPower(pas.WebState.A.LoadAvgW),"needed, on average") + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.BatteryNeedWh,0) + " Wh","battery needed for the night") + '</div><table class="tbl" style="margin-top:12px"><tr><th>Where the power goes</th><th class="n">Watts</th></tr>';
    for (var $l = 0, $end = rtl.length(pas.WebState.A.PowerLines) - 1; $l <= $end; $l++) {
      I = $l;
      Result = Result + "<tr><td>" + pas.WebState.A.PowerLines[I].Name + '</td><td class="n">' + pas.TsFmt.FmtNum(pas.WebState.A.PowerLines[I].Value,0) + "</td></tr>";
    };
    Result = Result + '<tr><td><b>Total needed</b></td><td class="n"><b>' + pas.TsFmt.FmtNum(pas.WebState.A.LoadAvgW,0) + "</b></td></tr></table>";
    return Result;
  };
  this.PlanInfo = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var I = 0;
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = '<div class="numgrid">' + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.DevYears),"to build and test") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.LaunchYear),"until launch") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.CruiseYears),"travelling") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.D.LifeYears),"of science planned") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.SuccessProb),"chance of finishing") + "</div>";
    if (pas.WebState.A.MissedDeadline) {
      Result = Result + '<p class="small" style="margin-top:8px;color:var(--warn)">This plan misses the deadline (' + $impl.DeadlineText(Sc) + ").</p>"}
     else Result = Result + '<p class="small muted" style="margin-top:8px">Deadline: ' + $impl.DeadlineText(Sc) + ". This plan meets it.</p>";
    Result = Result + '<table class="tbl" style="margin-top:12px"><tr><th>Where the money goes</th><th class="n">$ million</th></tr>';
    for (var $l = 0, $end = rtl.length(pas.WebState.A.CostLines) - 1; $l <= $end; $l++) {
      I = $l;
      Result = Result + "<tr><td>" + pas.WebState.A.CostLines[I].Name + '</td><td class="n">' + pas.TsFmt.FmtNum(pas.WebState.A.CostLines[I].Value,1) + "</td></tr>";
    };
    Result = Result + "<tr><td><b>Total</b> against a cap of " + pas.TsFmt.FmtMoney(pas.WebState.A.CapM) + '</td><td class="n"><b>' + pas.TsFmt.FmtNum(pas.WebState.A.CostTotal,1) + "</b></td></tr></table>";
    return Result;
  };
  this.ViewReview = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var I = 0;
    var Sev = 0;
    var R = 0;
    var AllGo = false;
    var CanLaunch = false;
    var List = "";
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = $impl.TopBar(2) + '<main class="wrap"><h4>Mission review board</h4><h2>' + Sc.Name + "</h2>";
    if (pas.WebState.A.Blockers > 0) {
      Result = Result + '<div class="verdict nogo" style="margin-top:14px"><div class="verdict-word">NO-GO</div><div><h3>' + pas.TsFmt.Plural(pas.WebState.A.Blockers,"thing","things") + " must be fixed before this mission can be approved.</h3>" + '<p class="muted">Real missions go through reviews like this many times. Each finding below says what is wrong, why it matters and what to try.</p></div></div>'}
     else Result = Result + '<div class="verdict go" style="margin-top:14px"><div class="verdict-word">GO</div><div><h3>The design is approved for flight' + pas.strutils.IfThen(pas.WebState.A.Warnings > 0,", with " + pas.TsFmt.Plural(pas.WebState.A.Warnings,"warning","warnings") + ".",".") + "</h3>" + '<p class="muted">You can launch now, or go back and squeeze out more science per dollar. You can fly the same mission as many times as you like.</p></div></div>';
    Result = Result + '<div class="two-col"><div>';
    List = "";
    for (var $l = 3; $l >= 0; $l--) {
      Sev = $l;
      for (var $l1 = 0, $end = rtl.length(pas.WebState.A.Findings) - 1; $l1 <= $end; $l1++) {
        I = $l1;
        if (pas.WebState.A.Findings[I].Sev === Sev) List = List + $impl.FindingHtml(pas.WebState.A.Findings[I],true);
      };
    };
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("list") + "<h3>Findings</h3></div>" + List + "</div></div><div>";
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("target") + '<h3>What to expect</h3></div><div class="numgrid">' + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.SciencePct,0) + " %","of the science goal") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.SuccessProb),"chance of finishing") + $impl.Num(pas.TsFmt.FmtMoney(pas.WebState.A.CostTotal),"of a " + pas.TsFmt.FmtMoney(pas.WebState.A.CapM) + " cap") + $impl.Num(pas.strutils.IfThen(pas.WebState.A.LvCapKg > 0,pas.TsFmt.FmtPct(pas.WebState.A.MassMargin),"none"),"launch mass margin") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.PowerMargin),"power margin") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.DataReturn),"of data gets home") + '</div><p class="small muted" style="margin-top:10px">Minimum for success: ' + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " % of the science goal. Odds: launch " + pas.TsFmt.FmtPct(pas.WebState.A.LaunchSuccess) + ", arrival " + pas.TsFmt.FmtPct(pas.WebState.A.InsertSuccess) + ", each year in space " + pas.TsFmt.FmtPct(pas.WebState.A.YearSurvival) + ".</p></div>";
    AllGo = true;
    if (pas.WebState.Players > 1) {
      Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("users") + "<h3>Go / no-go poll</h3></div>" + '<p class="small muted">Flight directors poll every position before a launch. Each of you must call GO. If your own goal is at risk, say so now and argue for a change.</p>';
      for (R = 0; R <= 3; R++) {
        Result = Result + '<div class="poll-row"><div class="who">' + pas.WebUtil.Chip("chip-" + pas.WebState.RoleClass(R),pas.TsTypes.RoleName[R]) + " <b>" + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(R)) + '</b><div class="small muted">' + pas.TsScore.RoleGoalText(R) + " ";
        if (pas.TsScore.RoleForecast(R,pas.WebState.A,pas.WebState.D)) {
          Result = Result + '<span style="color:var(--good)">On course.</span>'}
         else Result = Result + '<span style="color:var(--bad)">At risk.</span>';
        Result = Result + "</div></div>";
        if (pas.WebState.Votes[R]) {
          Result = Result + pas.WebUtil.Btn("btn btn-primary btn-small","vote",pas.SysUtils.IntToStr(R),pas.WebUtil.Icon("check") + "GO")}
         else {
          Result = Result + pas.WebUtil.Btn("btn btn-small","vote",pas.SysUtils.IntToStr(R),"Call GO");
          AllGo = false;
        };
        Result = Result + "</div>";
      };
      Result = Result + "</div>";
    };
    CanLaunch = (pas.WebState.A.Blockers === 0) && AllGo;
    Result = Result + '<div class="row" style="margin-top:14px">' + pas.WebUtil.Btn("btn","backlab","",pas.WebUtil.Icon("back") + "Back to the lab");
    if (CanLaunch) {
      Result = Result + pas.WebUtil.Btn("btn btn-primary btn-big","fly","",pas.WebUtil.IconLg("rocket") + "Build it and launch")}
     else if (pas.WebState.A.Blockers > 0) {
      Result = Result + pas.WebUtil.BtnOff("btn btn-primary btn-big","Fix the red findings first")}
     else Result = Result + pas.WebUtil.BtnOff("btn btn-primary btn-big","Waiting for every GO");
    Result = Result + "</div></div></div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewMission = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = $impl.TopBar(3) + '<main class="wrap"><div class="row" style="margin-bottom:12px"><div><h4>Mission control</h4><h2>' + Sc.Name + '</h2></div><span class="spacer"></span><span class="mono muted" id="m-clock"></span></div>' + '<div class="ops"><div><div class="stage"><canvas id="cv-main" width="1280" height="720" role="img" aria-label="Mission view"></canvas></div>' + '<div class="ops-controls" id="m-ctl"></div>' + '<div class="cv-box" id="m-chartbox" hidden><canvas id="cv-chart" width="1280" height="340" role="img" aria-label="Chart of science, power and data over time"></canvas></div>' + '<div class="section-head"><h3>Mission log</h3><span class="muted small">Newest first</span></div><div class="log" id="m-log"></div></div>' + '<aside id="m-side">' + $mod.ViewMissionSide() + "</aside></div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewMissionSide = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var I = 0;
    var N = 0;
    var Tone = "";
    var V = 0.0;
    var Spent = 0.0;
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Result = '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("target") + "<h3>" + pas.TsSim.PhaseName[pas.WebState.Sim.Phase] + "</h3></div>";
    Tone = "good";
    if (pas.WebState.Sim.SciencePct < Sc.ThresholdPct) Tone = "warn";
    Result = Result + $impl.Gauge("science","flask","Science returned",pas.TsFmt.FmtNum(pas.WebState.Sim.SciencePct,0) + " % of the goal",pas.WebState.Sim.SciencePct / 120,Tone,Sc.ThresholdPct / 120,"");
    N = rtl.length(pas.WebState.Sim.HistPower);
    if (N > 0) {
      V = pas.WebState.Sim.HistPower[N - 1] / 100;
      Tone = "good";
      if (V < 0.95) Tone = "warn";
      if (V < 0.6) Tone = "bad";
      Result = Result + $impl.Gauge("power","bolt","Power available",pas.TsFmt.FmtPct(V) + " of what is needed",V,Tone,-1,"");
      V = 1;
      if (pas.WebState.Sim.GenGbit > 0) V = pas.TsTypes.Clamp(pas.WebState.Sim.DownGbit / pas.WebState.Sim.GenGbit,0,1);
      Tone = "good";
      if (V < 0.8) Tone = "warn";
      if (V < 0.3) Tone = "bad";
      Result = Result + $impl.Gauge("data","data","Data sent home",pas.TsFmt.FmtData(pas.WebState.Sim.DownGbit) + " (" + pas.TsFmt.FmtPct(V) + ")",V,Tone,-1,"");
      V = pas.WebState.Sim.HistStore[N - 1] / 100;
      Tone = "good";
      if (V > 0.9) Tone = "warn";
      Result = Result + $impl.Gauge("data","cpu","Recorder",pas.TsFmt.FmtPct(V) + " full",V,Tone,-1,"");
    };
    if (pas.WebState.Sim.DvStart > 0) {
      V = pas.TsTypes.Clamp(pas.WebState.Sim.DvLeft / pas.WebState.Sim.DvStart,0,1);
      Tone = "good";
      if (V < 0.1) Tone = "warn";
      Result = Result + $impl.Gauge("mass","rocket","Speed change left",pas.TsFmt.FmtDv(Math.max(0,pas.WebState.Sim.DvLeft)),V,Tone,-1,"");
    };
    Spent = pas.TsSim.SimFinalCost(pas.WebState.Sim);
    Tone = "good";
    if (Spent > pas.WebState.Sim.A.CapM) Tone = "bad";
    Result = Result + $impl.Gauge("cost","coin","Spent",pas.TsFmt.FmtMoney(Spent) + " of " + pas.TsFmt.FmtMoney(pas.WebState.Sim.A.CapM),Spent / pas.WebState.Sim.A.CapM,Tone,-1,"") + "</div>";
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("flask") + '<h3>Instruments</h3></div><div class="instr-list">';
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
      I = $l;
      if ((I <= (rtl.length(pas.WebState.D.Instr) - 1)) && pas.WebState.D.Instr[I] && pas.TsEngine.InstrumentOffered(pas.WebState.Scen,I)) {
        if ((I <= (rtl.length(pas.WebState.Sim.InstrAlive) - 1)) && pas.WebState.Sim.InstrAlive[I]) {
          Result = Result + "<div><span>" + pas.TsCatalog.Instruments[I].Name + "</span>" + pas.WebUtil.Chip("chip-good","working") + "</div>"}
         else Result = Result + '<div><span class="dead">' + pas.TsCatalog.Instruments[I].Name + "</span>" + pas.WebUtil.Chip("chip-bad","lost") + "</div>";
      };
    };
    Result = Result + "</div>";
    if (Sc.UsesEonet) Result = Result + '<p class="small" style="margin-top:10px"><b>' + pas.SysUtils.IntToStr(pas.WebState.Sim.EventsSeen) + "</b> real events observed so far.</p>";
    Result = Result + "</div>";
    return Result;
  };
  this.ViewMissionControls = function (Running, Done, InLaunch, Speed) {
    var Result = "";
    var I = 0;
    var Cls = "";
    if (Done) {
      Result = pas.WebUtil.Btn("btn btn-primary btn-big","report","",pas.WebUtil.IconLg("trophy") + "See the mission report");
      return Result;
    };
    if (InLaunch) {
      Result = pas.WebUtil.Btn("btn","skiplaunch","",pas.WebUtil.Icon("skip") + "Skip the launch");
      return Result;
    };
    if (Running) {
      Result = pas.WebUtil.Btn("btn btn-primary","pause","",pas.WebUtil.Icon("pause") + "Pause")}
     else Result = pas.WebUtil.Btn("btn btn-primary","play","",pas.WebUtil.Icon("play") + "Run");
    Result = Result + '<div class="seg" role="group" aria-label="Speed">';
    for (I = 1; I <= 3; I++) {
      Cls = "seg-btn";
      if (I === Speed) Cls = Cls + " on";
      var $tmp = I;
      if ($tmp === 1) {
        Result = Result + pas.WebUtil.Btn(Cls,"speed","1","Slow")}
       else if ($tmp === 2) {
        Result = Result + pas.WebUtil.Btn(Cls,"speed","2","Fast")}
       else {
        Result = Result + pas.WebUtil.Btn(Cls,"speed","3","Fastest");
      };
    };
    Result = Result + '</div><div class="progress" aria-hidden="true"><i id="m-prog"></i></div>';
    return Result;
  };
  this.LogItemHtml = function (Idx) {
    var Result = "";
    var E = pas.TsSim.TSimEvent.$new();
    var Tn = "";
    E.$assign(pas.WebState.Sim.Log[Idx]);
    var $tmp = E.Tone;
    if ($tmp === 1) {
      Tn = "tn-good"}
     else if ($tmp === 2) {
      Tn = "tn-warn"}
     else if ($tmp === 3) {
      Tn = "tn-bad"}
     else if ($tmp === 4) {
      Tn = "tn-real"}
     else {
      Tn = "";
    };
    Result = '<div class="log-item ' + Tn + '"><div class="log-head"><span class="log-when">' + $impl.WhenText(E) + "</span>" + '<span class="log-title">' + E.Title + "</span>";
    if (E.Tone === 4) Result = Result + pas.WebUtil.Chip("chip-real","Real NASA data");
    if (E.IsDecision) Result = Result + $impl.OwnerChip(E.Owner);
    Result = Result + "</div><p>" + E.Text + "</p>";
    if (E.IsDecision) Result = Result + '<p class="decided"><b>Decision:</b> ' + E.Decision + ". " + E.Outcome + "</p>";
    if (E.Source !== "") Result = Result + '<p class="src">' + E.Source + "</p>";
    if (E.Lesson !== "") Result = Result + '<p class="lesson">' + E.Lesson + "</p>";
    Result = Result + "</div>";
    return Result;
  };
  this.ViewReport = function () {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var I = 0;
    var R = 0;
    var Stars = "";
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    Stars = "";
    for (I = 1; I <= 5; I++) if (I <= pas.WebState.Card.Stars) {
      Stars = Stars + "&#9733;"}
     else Stars = Stars + "<i>&#9733;</i>";
    Result = $impl.TopBar(4) + '<main class="wrap"><div class="panel"><div class="report-head">' + '<div class="grade"><b>' + pas.WebState.Card.Grade + "</b><span>grade</span></div><div><h4>" + Sc.Name + " &middot; mission report</h4>" + "<h2>" + pas.WebState.Card.Outcome + '</h2><p class="lead" style="margin-top:4px">' + pas.WebState.Card.OutcomeText + "</p>" + '<p style="margin-top:8px"><span class="stars">' + Stars + '</span> <b class="mono" style="font-size:20px;margin-left:8px">' + pas.SysUtils.IntToStr(pas.WebState.Card.Total) + '</b> <span class="muted">of 1,000 &middot; ' + pas.WebState.Card.Title + "</span></p></div></div></div>";
    Result = Result + '<div class="two-col"><div>' + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("list") + "<h3>What happened, and why</h3></div>";
    for (var $l = 0, $end = rtl.length(pas.WebState.Card.Insights) - 1; $l <= $end; $l++) {
      I = $l;
      Result = Result + '<div class="insight ' + $impl.SevClass(pas.WebState.Card.Insights[I].Tone) + '"><b>' + pas.WebState.Card.Insights[I].Title + "</b><p>" + pas.WebState.Card.Insights[I].Text + "</p>";
      if (pas.WebState.Card.Insights[I].Tip !== "") Result = Result + '<p class="tip"><b>Next time:</b> ' + pas.WebState.Card.Insights[I].Tip + "</p>";
      Result = Result + "</div>";
    };
    Result = Result + "</div>";
    if (rtl.length(pas.WebState.Sim.HistScience) > 2) Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("target") + "<h3>The mission, week by week</h3></div>" + '<div class="cv-box"><canvas id="cv-chart" width="1280" height="340" role="img" aria-label="Chart of science, power and data over time"></canvas></div></div>';
    if (pas.WebState.Card.Analog >= 0) Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("rocket") + "<h3>The real mission most like yours</h3></div><p>" + pas.WebState.Card.AnalogText + '</p><p class="muted" style="margin-top:6px">' + Sc.Analogs[pas.WebState.Card.Analog].Blurb + " " + pas.WebUtil.Link(Sc.Analogs[pas.WebState.Card.Analog].Url,"Read about it") + "</p></div>";
    Result = Result + "</div><div>";
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("trophy") + "<h3>Score</h3></div>" + $impl.SBar("Science",pas.WebState.Card.Science,0.45) + $impl.SBar("Survival",pas.WebState.Card.Survival,0.15) + $impl.SBar("Budget",pas.WebState.Card.Budget,0.15) + $impl.SBar("Engineering",pas.WebState.Card.Engineering,0.15) + $impl.SBar("Value for money",pas.WebState.Card.Efficiency,0.1) + '<div class="numgrid" style="margin-top:12px">' + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.Card.SciencePct,0) + " %","of the science goal") + $impl.Num(pas.TsFmt.FmtMoney(pas.WebState.Card.FinalCostM),"spent, cap " + pas.TsFmt.FmtMoney(pas.WebState.Card.CapM)) + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.Card.YearsFlown),"of science flown") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.Card.ReturnFrac),"of data sent home");
    if (Sc.UsesEonet) Result = Result + $impl.Num(pas.SysUtils.IntToStr(pas.WebState.Sim.EventsSeen),"real events observed");
    Result = Result + "</div></div>";
    if (pas.WebState.Players > 1) {
      Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("users") + "<h3>Crew goals: " + pas.SysUtils.IntToStr(pas.WebState.Card.RolesMet) + " of 4 met</h3></div>";
      for (R = 0; R <= 3; R++) {
        Result = Result + '<div class="poll-row"><div class="who">' + pas.WebUtil.Chip("chip-" + pas.WebState.RoleClass(R),pas.TsTypes.RoleName[R]) + " <b>" + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(R)) + '</b><div class="small muted">' + pas.TsScore.RoleGoalText(R) + '</div><div class="small">' + pas.WebState.Card.RoleResult[R] + "</div></div>";
        if (pas.WebState.Card.RoleMet[R]) {
          Result = Result + pas.WebUtil.Chip("chip-good",pas.WebUtil.Icon("check") + "Met")}
         else Result = Result + pas.WebUtil.Chip("chip-bad",pas.WebUtil.Icon("x") + "Missed");
        Result = Result + "</div>";
      };
      Result = Result + "</div>";
    };
    Result = Result + '<div class="panel"><div class="panel-title">' + pas.WebUtil.Icon("redo") + '<h3>What next?</h3></div><div class="stack">' + pas.WebUtil.Btn("btn btn-primary","improve","",pas.WebUtil.Icon("wrench") + "Improve this design and fly again") + pas.WebUtil.Btn("btn","refly","",pas.WebUtil.Icon("redo") + "Fly the same design again (new luck)") + pas.WebUtil.Btn("btn","share","",pas.WebUtil.Icon("share") + "Challenge someone with this design") + pas.WebUtil.Btn("btn","log","",pas.WebUtil.Icon("trophy") + "Mission log and rankings") + pas.WebUtil.Btn("btn","start","",pas.WebUtil.Icon("rocket") + "Start a different mission") + "</div></div>";
    Result = Result + "</div></div>";
    Result = Result + '<div class="section-head"><h3>Full mission log</h3></div><div class="log">';
    for (var $l1 = rtl.length(pas.WebState.Sim.Log) - 1; $l1 >= 0; $l1--) {
      I = $l1;
      Result = Result + $mod.LogItemHtml(I);
    };
    Result = Result + "</div></main>" + $impl.Footer();
    return Result;
  };
  this.ViewLog = function () {
    var Result = "";
    var L = [];
    var I = 0;
    var J = 0;
    var T = 0;
    var Order = [];
    L = pas.WebStore.LoadLog();
    Result = $impl.TopBar(-1) + '<main class="wrap"><div class="row"><div><h4>Mission log</h4><h2>Every mission flown on this device</h2></div>' + '<span class="spacer"></span>' + pas.WebUtil.Btn("btn","start","",pas.WebUtil.Icon("rocket") + "Start a mission") + "</div>";
    if (rtl.length(L) === 0) {
      Result = Result + '<div class="panel" style="margin-top:16px"><p>No missions flown yet. Your results will be ranked here, best first, ' + "so you can compare designs and crews.</p></div></main>" + $impl.Footer();
      return Result;
    };
    Order = rtl.arraySetLength(Order,0,rtl.length(L));
    for (var $l = 0, $end = rtl.length(L) - 1; $l <= $end; $l++) {
      I = $l;
      Order[I] = I;
    };
    for (var $l1 = 0, $end1 = rtl.length(Order) - 1 - 1; $l1 <= $end1; $l1++) {
      I = $l1;
      for (var $l2 = I + 1, $end2 = rtl.length(Order) - 1; $l2 <= $end2; $l2++) {
        J = $l2;
        if (L[Order[J]].Score > L[Order[I]].Score) {
          T = Order[I];
          Order[I] = Order[J];
          Order[J] = T;
        };
      };
    };
    Result = Result + '<div class="panel" style="margin-top:16px"><div class="tbl-scroll"><table class="tbl"><tr><th>Rank</th><th>Mission</th><th>Crew</th>' + '<th class="n">Score</th><th>Grade</th><th class="n">Science</th><th class="n">Cost</th><th>Result</th><th>Date</th><th></th></tr>';
    for (var $l3 = 0, $end3 = rtl.length(Order) - 1; $l3 <= $end3; $l3++) {
      I = $l3;
      J = Order[I];
      Result = Result + '<tr><td class="n">' + pas.SysUtils.IntToStr(I + 1) + "</td><td>" + pas.WebUtil.Esc(L[J].ScenarioName) + "</td><td>" + pas.WebUtil.Esc(L[J].Crew) + '</td><td class="n"><b>' + pas.SysUtils.IntToStr(L[J].Score) + "</b></td><td>" + pas.WebUtil.Esc(L[J].Grade) + '</td><td class="n">' + pas.TsFmt.FmtNum(L[J].SciencePct,0) + ' %</td><td class="n">' + pas.TsFmt.FmtMoney(L[J].CostM) + "</td><td>" + pas.WebUtil.Esc(L[J].Outcome) + "</td><td>" + pas.WebUtil.Esc(L[J].Date) + "</td><td>" + pas.WebUtil.Btn("btn btn-small","loadlog",pas.SysUtils.IntToStr(J),"Open design") + "</td></tr>";
    };
    Result = Result + '</table></div><div class="row" style="margin-top:14px">' + '<span class="muted small">Saved in this browser only. Send someone a design with Share, then compare scores on the same mission.</span><span class="spacer"></span>' + pas.WebUtil.Btn("btn btn-danger btn-small","clearlog","","Clear the log") + "</div></div></main>" + $impl.Footer();
    return Result;
  };
  this.ModalHelp = function () {
    var Result = "";
    Result = $impl.ModalShell("How to play","<p>You are a mission design team. A space agency has asked for a mission and set a cost cap and a deadline. " + "Your job is to return as much science as you can without breaking either.</p>" + '<dl class="gloss">' + "<dt>1. Read the briefing</dt><dd>It says what the science team wants measured and what makes this destination hard.</dd>" + "<dt>2. Design in the lab</dt><dd>Work through the seven tabs: orbit, payload, spacecraft, power, comms, launch and plan. " + "The gauges on the right show cost, mass, power, data, science and schedule. Change one thing and watch the others move. That ripple is the whole game.</dd>" + "<dt>3. Go to the review board</dt><dd>It lists what would stop the mission (red) and what might hurt it (amber), and explains each one. Fix the red ones. Decide which amber ones you can live with.</dd>" + "<dt>4. Fly</dt><dd>Things go wrong during development and in flight, some of them real solar storms from NASA records. You will be asked to decide.</dd>" + "<dt>5. Read the report</dt><dd>It tells you why the mission scored what it did and which real mission yours resembles. Then improve the design and fly again.</dd>" + "<dt>Playing as a crew</dt><dd>Two to four players share one screen. Each owns some of the tabs and has a personal goal. " + "The science lead wants more instruments, the engineer wants margin, the operations lead wants every bit sent home and the project manager wants it on budget. You have to negotiate.</dd>" + "<dt>There is no single right answer</dt><dd>A small, cheap spacecraft and a big, capable one can both score well. Try both.</dd></dl>" + '<div class="row" style="margin-top:16px">' + pas.WebUtil.Btn("btn btn-primary","close","","Got it") + "</div>",true);
    return Result;
  };
  this.ModalGlossary = function () {
    var Result = "";
    var I = 0;
    var S = "";
    S = '<p class="muted">Plain-language meanings of the terms used in the game.</p><dl class="gloss">';
    for (var $l = 0, $end = rtl.length(pas.TsCatalog.Glossary) - 1; $l <= $end; $l++) {
      I = $l;
      S = S + "<dt>" + pas.TsCatalog.Glossary[I].Term + "</dt><dd>" + pas.TsCatalog.Glossary[I].Plain + '</dd><dd class="why">' + pas.TsCatalog.Glossary[I].Why + "</dd>";
    };
    S = S + "</dl>";
    Result = $impl.ModalShell("Glossary",S,true);
    return Result;
  };
  this.ModalAbout = function () {
    var Result = "";
    Result = $impl.ModalShell("About TradeSpace","<p>TradeSpace was built for the 2026 NASA Space Apps Challenge, &ldquo;Space Mission Design Game&rdquo;. It is not affiliated with or endorsed by NASA.</p>" + "<p>The whole game is written in Object Pascal (the Delphi language) and compiled for the browser with the open-source pas2js compiler.</p>" + '<dl class="gloss"><dt>NASA data used while you play</dt>' + "<dd>" + pas.WebUtil.Link("https://eonet.gsfc.nasa.gov/","EONET") + ": real natural events are the targets and set the science priorities of Disaster Watch.</dd>" + "<dd>" + pas.WebUtil.Link("https://ccmc.gsfc.nasa.gov/tools/DONKI/","DONKI") + ": real solar flares, particle storms and geomagnetic storms strike your spacecraft.</dd>" + "<dd>" + pas.WebUtil.Link("https://api.nasa.gov/","NeoWs") + " and JPL: the real 2029 Apophis flyby sets the deadline of Race to Apophis.</dd>" + "<dd>" + pas.WebUtil.Link("https://www.earthdata.nasa.gov/engage/open-data-services-software/earthdata-developer-portal/gibs-api","GIBS") + ": the Blue Marble world map.</dd>" + "<dd>NASA image KSC-08pd1628 (sunset over the Kennedy Space Center turn basin): the launch sky and clouds.</dd>" + "<dt>NASA resources that shaped the design</dt>" + "<dd>" + pas.WebUtil.Link("https://www.nasa.gov/wp-content/uploads/2025/04/250323-design-and-develop-science-mission.pdf","Design and Develop Science Missions") + ", JPL " + pas.WebUtil.Link("https://dataverse.jpl.nasa.gov/dataset.xhtml?persistentId=hdl:2014/44299","Concept Maturity Levels") + ", the " + pas.WebUtil.Link("https://etd.gsfc.nasa.gov/capabilities/integrated-design-center/mission-design-lab/","Goddard Mission Design Lab") + ", " + pas.WebUtil.Link("https://software.nasa.gov/software/GSC-19468-1","GMAT") + ", " + pas.WebUtil.Link("https://nasa.github.io/mission-viz/","Mission Viz") + ", " + pas.WebUtil.Link("https://www3.nasa.gov/sites/default/files/atoms/files/nasa_csli_cubesat_101_508.pdf","CubeSat 101") + " and the Webb " + pas.WebUtil.Link("https://science.nasa.gov/mission/webb/game-build-it-yourself/","Build It Yourself") + " game.</dd>" + "<dt>Space agency partners</dt><dd>Rockets, missions and instruments from ISRO, ESA, JAXA, CSA, ASI, KASA and the UAE appear throughout, with links to their mission pages.</dd>" + "<dt>Numbers</dt><dd>Masses, costs, data rates and rocket capacities are simplified from public figures and rounded for teaching. They are not engineering data.</dd>" + "<dt>Use of AI</dt><dd>The program code, the in-game text and the code that draws the graphics were written with the help of Claude, an AI model made by Anthropic. " + "No AI-generated images, audio or video are used: every picture is drawn by the game from the numbers in your design, or is a NASA photograph.</dd></dl>",true);
    return Result;
  };
  this.ModalBreakdown = function (Which) {
    var Result = "";
    var Sc = pas.TsTypes.TScenario.$new();
    var O = pas.TsTypes.TOrbit.$new();
    var M = 0;
    var S = "";
    Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
    O.$assign(Sc.Orbits[pas.WebState.D.Orbit]);
    if (Which === "cost") {
      Result = $impl.ModalShell("Where the money goes",$impl.LinesTable(pas.WebState.A.CostLines,"Item","$ million",1) + '<p class="lesson">The cap is ' + pas.TsFmt.FmtMoney(pas.WebState.A.CapM) + ". Management, assembly and test add about 23 % to the hardware. Operations are paid every year the mission flies. " + "Reserves are only spent if something goes wrong.</p>",false)}
     else if (Which === "mass") {
      Result = $impl.ModalShell("Where the mass goes",$impl.LinesTable(pas.WebState.A.MassLines,"Item","kg",1) + '<p class="lesson">Propellant comes from the rocket equation: to change speed by ' + pas.TsFmt.FmtDv(pas.WebState.A.DvNeed) + " the spacecraft must burn a fixed share of its own mass. Add 1 kg of equipment and the propellant grows too. " + pas.strutils.IfThen(pas.WebState.A.LvCapKg > 0,"Your rocket can send " + pas.TsFmt.FmtMass(pas.WebState.A.LvCapKg) + " to " + pas.TsEngine.LaunchTargetName(pas.WebState.D) + ".","No rocket has been chosen yet.") + "</p>",false)}
     else if (Which === "power") {
      Result = $impl.ModalShell("Where the power goes",$impl.LinesTable(pas.WebState.A.PowerLines,"Load","watts",0) + '<p class="lesson">The array makes ' + pas.TsFmt.FmtPower(pas.WebState.A.SolarW) + " in full sun here" + pas.strutils.IfThen(pas.WebState.A.RtgW > 0,", plus " + pas.TsFmt.FmtPower(pas.WebState.A.RtgW) + " from nuclear batteries","") + ". With " + pas.TsFmt.FmtPct(O.EclipseFrac) + " of each orbit in shadow and the battery to refill, that averages " + pas.TsFmt.FmtPower(pas.WebState.A.GenAvgW) + ". Margin: " + pas.TsFmt.FmtPct(pas.WebState.A.PowerMargin) + ".</p>",false)}
     else if (Which === "data") {
      Result = $impl.ModalShell("The data link",'<div class="numgrid">' + $impl.Num(pas.TsFmt.FmtData(pas.WebState.A.GenGbitDay),"recorded a day") + $impl.Num(pas.TsFmt.FmtRate(pas.WebState.A.RateAvgMbps),"typical rate") + $impl.Num(pas.TsFmt.FmtRate(pas.WebState.A.RateMinMbps),"slowest rate") + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.ContactHr,1) + " h","contact a day") + $impl.Num(pas.TsFmt.FmtData(pas.WebState.A.DownGbitDay),"sent a day") + $impl.Num(pas.TsFmt.FmtData(pas.WebState.A.StorageGbit),"recorder size") + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.LightDelayMin,1) + " min","signal travel time") + "</div>" + '<p class="lesson">Rate = transmitter power &times; dish area &times; band &times; ground antenna, divided by distance squared. ' + "Twice as far means a quarter of the data. The recorder bridges the gaps between contacts.</p>",false)}
     else if (Which === "science") {
      S = '<table class="tbl"><tr><th>Measurement</th><th class="n">Wanted</th><th class="n">Your payload</th></tr>';
      for (M = 0; M <= 8; M++) if (Sc.Weight[M] >= 0.1) S = S + "<tr><td>" + pas.TsTypes.MeasureName[M] + '</td><td class="n">' + $impl.PriorityWord(Sc.Weight[M]) + '</td><td class="n">' + pas.TsFmt.FmtNum(pas.WebState.A.Capability[M],0) + "</td></tr>";
      S = S + '</table><p class="lesson">Your payload could reach ' + pas.TsFmt.FmtNum(pas.WebState.A.ScienceMaxPct,0) + " % of the goal given unlimited time. In " + pas.TsFmt.FmtYears(Math.min(pas.WebState.D.LifeYears,pas.WebState.A.LifeLimitYears)) + " it should reach " + pas.TsFmt.FmtNum(pas.WebState.A.SciencePct,0) + " %. Too little power or a data bottleneck slows it down. The minimum for success is " + pas.TsFmt.FmtNum(Sc.ThresholdPct,0) + " %.</p>";
      Result = $impl.ModalShell("Predicted science",S,false);
    } else if (Which === "time") {
      Result = $impl.ModalShell("The schedule",'<div class="numgrid">' + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.DevYears),"to build and test") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.LaunchYear),"until launch") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.CruiseYears),"travelling") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.A.ArriveYear),"until arrival") + $impl.Num(pas.TsFmt.FmtYears(pas.WebState.D.LifeYears),"of science planned") + "</div>" + '<p class="lesson">' + $impl.DeadlineText(Sc) + ". Bigger buses and complicated instruments take longer to build. " + pas.strutils.IfThen(Sc.WindowYears > 0,"Launch windows to " + Sc.Body + " open every " + pas.TsFmt.FmtYears(Sc.WindowPeriod) + ". ","") + "An accelerated schedule buys time with money and risk.</p>",false)}
     else Result = $impl.ModalShell("The odds",'<div class="numgrid">' + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.LaunchSuccess),"launch") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.InsertSuccess),"arrival") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.YearSurvival),"each year in space") + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.AnomalyRate,2),"faults expected a year") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.SuccessProb),"finishing the whole plan") + "</div>" + '<p class="lesson">The chances multiply. A more proven rocket, a higher risk class with more backups, and proper radiation protection all raise them. ' + "About one fault in five ends a mission. The rest cost you an instrument, your pointing or a few weeks in safe mode.</p>",false);
    return Result;
  };
  this.ModalDecision = function () {
    var Result = "";
    var E = pas.TsSim.TSimEvent.$new();
    var I = 0;
    var S = "";
    E.$assign(pas.WebState.Sim.Pending);
    S = "";
    if (pas.WebState.Players > 1) S = "<p>" + pas.WebUtil.Chip("chip-" + pas.WebState.RoleClass(E.Owner),pas.TsTypes.RoleName[E.Owner]) + " <b>" + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(E.Owner)) + ", this one is yours.</b> Talk it over, then decide.</p>";
    S = S + "<p>" + E.Text + "</p>";
    if (E.Source !== "") S = S + "<p>" + pas.WebUtil.Chip("chip-real","Real NASA data") + ' <span class="small muted">' + E.Source + "</span></p>";
    S = S + '<div class="choices">';
    for (var $l = 0, $end = rtl.length(E.Choices) - 1; $l <= $end; $l++) {
      I = $l;
      S = S + '<button type="button" class="choice" data-act="choose" data-a="' + pas.SysUtils.IntToStr(I) + '"><b>' + E.Choices[I].Text + "</b><span>" + E.Choices[I].Hint + "</span></button>";
    };
    S = S + "</div>";
    if (E.Lesson !== "") S = S + '<p class="lesson">' + E.Lesson + "</p>";
    Result = '<div class="modal" role="dialog" aria-modal="true" aria-label="' + E.Title + '"><div class="modal-head"><h2>' + E.Title + "</h2>" + pas.WebUtil.Chip("chip-warn","Decision") + "</div>" + S + "</div>";
    return Result;
  };
  this.ModalOutcome = function (Idx) {
    var Result = "";
    var E = pas.TsSim.TSimEvent.$new();
    var Cls = "";
    E.$assign(pas.WebState.Sim.Log[Idx]);
    var $tmp = E.Tone;
    if ($tmp === 1) {
      Cls = "f-good"}
     else if ($tmp === 3) {
      Cls = "f-block"}
     else {
      Cls = "f-info";
    };
    Result = '<div class="modal" role="dialog" aria-modal="true" aria-label="Outcome"><div class="modal-head"><h2>' + E.Title + "</h2></div>" + '<p class="muted">You chose: ' + E.Decision + '</p><div class="finding ' + Cls + '" style="margin-top:10px"><p style="margin:0">' + E.Outcome + '</p></div><div class="row" style="margin-top:16px">' + pas.WebUtil.Btn("btn btn-primary","resume","","Carry on " + pas.WebUtil.Icon("next")) + "</div></div>";
    return Result;
  };
  this.ModalShare = function (Url) {
    var Result = "";
    Result = $impl.ModalShell("Share this design","<p>Anyone who opens this link gets your exact design and the same run of luck, so you can compare scores on equal terms.</p>" + '<p><input type="text" readonly id="share-url" value="' + pas.WebUtil.Esc(Url) + '" style="width:100%;background:var(--bg);color:var(--text);' + 'border:1px solid var(--line2);border-radius:8px;padding:10px;font:13px var(--mono)" aria-label="Link to this design"></p>' + '<div class="row" style="margin-top:12px">' + pas.WebUtil.Btn("btn btn-primary","copyshare","",pas.WebUtil.Icon("share") + "Copy the link") + "</div>",false);
    return Result;
  };
  $mod.$implcode = function () {
    var Names = ["Concept","Design","Review","Fly","Report"];
    $impl.TopBar = function (Phase) {
      var Result = "";
      var I = 0;
      var Cls = "";
      Result = '<header class="topbar">' + '<button type="button" class="brand" data-act="home" title="Back to the start">TRADE<span>SPACE</span></button>';
      if (Phase >= 0) {
        Result = Result + '<nav class="phase-track" aria-label="Mission phases">';
        for (I = 0; I <= 4; I++) {
          Cls = "ph";
          if (I < Phase) {
            Cls = "ph done"}
           else if (I === Phase) Cls = "ph on";
          Result = Result + '<span class="' + Cls + '">' + pas.SysUtils.IntToStr(I + 1) + " " + Names[I] + "</span>";
        };
        Result = Result + "</nav>";
      };
      Result = Result + '<div class="topbar-right">' + pas.WebUtil.Btn("btn btn-ghost btn-small","glossary","",pas.WebUtil.Icon("book") + "Glossary") + pas.WebUtil.Btn("btn btn-ghost btn-small","help","",pas.WebUtil.Icon("info") + "How to play") + "</div></header>";
      return Result;
    };
    $impl.Footer = function () {
      var Result = "";
      Result = '<footer class="foot">TradeSpace was made for the 2026 NASA Space Apps Challenge. ' + "It is not affiliated with or endorsed by NASA. Data: NASA EONET, DONKI, NeoWs and GIBS. " + '<button type="button" class="btn btn-ghost btn-small" data-act="about">About, sources and AI disclosure</button></footer>';
      return Result;
    };
    $impl.Stat = function (ALabel, AValue) {
      var Result = "";
      Result = "<span><i>" + ALabel + "</i> " + AValue + "</span>";
      return Result;
    };
    $impl.KV = function (ALabel, AValue) {
      var Result = "";
      Result = '<div class="kv"><span class="muted">' + ALabel + "</span><b>" + AValue + "</b></div>";
      return Result;
    };
    $impl.Fact = function (AValue, ALabel) {
      var Result = "";
      Result = '<div class="fact"><b>' + AValue + "</b><span>" + ALabel + "</span></div>";
      return Result;
    };
    $impl.Num = function (AValue, ALabel) {
      var Result = "";
      Result = '<div class="num"><b>' + AValue + "</b><span>" + ALabel + "</span></div>";
      return Result;
    };
    $impl.Dots = function (Level) {
      var Result = "";
      var I = 0;
      Result = '<span class="dots" title="Difficulty ' + pas.SysUtils.IntToStr(Level) + ' of 3">';
      for (I = 1; I <= 3; I++) if (I <= Level) {
        Result = Result + '<i class="on"></i>'}
       else Result = Result + "<i></i>";
      Result = Result + "</span>";
      return Result;
    };
    $impl.SevClass = function (S) {
      var Result = "";
      var $tmp = S;
      if ($tmp === 3) {
        Result = "f-block"}
       else if ($tmp === 2) {
        Result = "f-warn"}
       else if ($tmp === 1) {
        Result = "f-info"}
       else {
        Result = "f-good";
      };
      return Result;
    };
    $impl.SevChip = function (S) {
      var Result = "";
      var $tmp = S;
      if ($tmp === 3) {
        Result = pas.WebUtil.Chip("chip-bad",pas.WebUtil.Icon("block") + "Must fix")}
       else if ($tmp === 2) {
        Result = pas.WebUtil.Chip("chip-warn",pas.WebUtil.Icon("warn") + "Warning")}
       else if ($tmp === 1) {
        Result = pas.WebUtil.Chip("chip-info",pas.WebUtil.Icon("info") + "Note")}
       else {
        Result = pas.WebUtil.Chip("chip-good",pas.WebUtil.Icon("check") + "Good");
      };
      return Result;
    };
    $impl.OwnerChip = function (R) {
      var Result = "";
      if (pas.WebState.Players <= 1) {
        Result = ""}
       else Result = pas.WebUtil.Chip("chip-" + pas.WebState.RoleClass(R),pas.TsTypes.RoleShort[R] + " &middot; " + pas.WebUtil.Esc(pas.WebState.RoleOwnerName(R)));
      return Result;
    };
    $impl.FindingHtml = function (F, WithOwner) {
      var Result = "";
      Result = '<div class="finding ' + $impl.SevClass(F.Sev) + '"><div class="finding-title">' + $impl.SevChip(F.Sev) + "<span>" + F.Title + "</span>";
      if (WithOwner) Result = Result + $impl.OwnerChip(F.Owner);
      Result = Result + "</div><p>" + F.Why + '</p><p class="fix"><b>Try:</b> ' + F.Fix + "</p></div>";
      return Result;
    };
    $impl.Gauge = function (Key, IconName, AName, AValue, Fill, Tone, Mark, DeltaHtml) {
      var Result = "";
      Result = '<button type="button" class="gauge" data-act="gauge" data-a="' + Key + '" title="Show the breakdown">' + '<div class="gauge-head"><span class="gauge-name">' + pas.WebUtil.Icon(IconName) + AName + "</span>" + '<span class="gauge-val">' + AValue + DeltaHtml + "</span></div>" + '<div class="gauge-bar"><div class="gauge-fill ' + Tone + '" style="width:' + pas.TsFmt.FmtNum(pas.TsTypes.Clamp(Fill,0,1) * 100,1) + '%"></div>';
      if (Mark >= 0) Result = Result + '<div class="gauge-mark" style="left:' + pas.TsFmt.FmtNum(pas.TsTypes.Clamp(Mark,0,1) * 100,1) + '%"></div>';
      Result = Result + "</div></button>";
      return Result;
    };
    $impl.Delta = function (Change, Txt, MoreIsWorse) {
      var Result = "";
      var Cls = "";
      Result = "";
      if (!pas.WebState.HasPrev) return Result;
      if (Math.abs(Change) < 1.0e-9) return Result;
      if ((Change > 0) === MoreIsWorse) {
        Cls = "worse"}
       else Cls = "better";
      Result = '<span class="delta ' + Cls + '">' + Txt + "</span>";
      return Result;
    };
    $impl.Signed = function (X, S) {
      var Result = "";
      if (X >= 0) {
        Result = "+" + S}
       else Result = "-" + S;
      return Result;
    };
    $impl.DeadlineText = function (Sc) {
      var Result = "";
      if (Sc.ArriveBy) {
        Result = "Arrive within " + pas.TsFmt.FmtYears(Sc.DeadlineYears)}
       else if (Sc.WindowYears > 0) {
        Result = "Launch within " + pas.TsFmt.FmtYears(Sc.DeadlineYears)}
       else Result = "Launch within " + pas.TsFmt.FmtYears(Sc.DeadlineYears);
      return Result;
    };
    $impl.PriorityWord = function (W) {
      var Result = "";
      if (W >= 0.95) {
        Result = "Top priority"}
       else if (W >= 0.7) {
        Result = "High"}
       else if (W >= 0.4) {
        Result = "Medium"}
       else Result = "Low";
      return Result;
    };
    $impl.PriorityBars = function (WithHave) {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      var M = 0;
      var Order = [];
      var I = 0;
      var J = 0;
      var N = 0;
      var T = 0;
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      Order = rtl.arraySetLength(Order,0,0);
      for (M = 0; M <= 8; M++) if (Sc.Weight[M] >= 0.1) {
        N = rtl.length(Order);
        Order = rtl.arraySetLength(Order,0,N + 1);
        Order[N] = M;
      };
      for (var $l = 0, $end = rtl.length(Order) - 1 - 1; $l <= $end; $l++) {
        I = $l;
        for (var $l1 = I + 1, $end1 = rtl.length(Order) - 1; $l1 <= $end1; $l1++) {
          J = $l1;
          if (Sc.Weight[Order[J]] > Sc.Weight[Order[I]]) {
            T = Order[I];
            Order[I] = Order[J];
            Order[J] = T;
          };
        };
      };
      Result = "";
      for (var $l2 = 0, $end2 = rtl.length(Order) - 1; $l2 <= $end2; $l2++) {
        I = $l2;
        M = Order[I];
        Result = Result + '<div class="wbar" title="' + pas.TsTypes.MeasureHint[M] + '"><span>' + pas.TsTypes.MeasureName[M] + "</span>" + '<div class="wbar-track"><div class="wbar-fill" style="width:' + pas.TsFmt.FmtNum(Sc.Weight[M] * 100,0) + '%;opacity:0.45"></div>';
        if (WithHave && pas.WebState.HasDesign) Result = Result + '<div class="wbar-have" style="width:' + pas.TsFmt.FmtNum(pas.TsTypes.Clamp(pas.WebState.A.Capability[M] / 100,0,1) * Sc.Weight[M] * 100,0) + '%"></div>';
        Result = Result + '</div><span class="muted tiny">';
        if (WithHave && pas.WebState.HasDesign) {
          Result = Result + pas.TsFmt.FmtNum(pas.WebState.A.Capability[M],0)}
         else Result = Result + $impl.PriorityWord(Sc.Weight[M]);
        Result = Result + "</span></div>";
      };
      return Result;
    };
    $impl.EventLegend = function () {
      var Result = "";
      var Cats = [];
      var Cnt = [];
      var I = 0;
      var J = 0;
      var N = 0;
      var Found = false;
      Cats = rtl.arraySetLength(Cats,"",0);
      Cnt = rtl.arraySetLength(Cnt,0,0);
      for (var $l = 0, $end = rtl.length(pas.TsScenarios.EarthEvents) - 1; $l <= $end; $l++) {
        I = $l;
        Found = false;
        for (var $l1 = 0, $end1 = rtl.length(Cats) - 1; $l1 <= $end1; $l1++) {
          J = $l1;
          if (Cats[J] === pas.TsScenarios.EarthEvents[I].Category) {
            Cnt[J] += 1;
            Found = true;
            break;
          };
        };
        if (!Found) {
          N = rtl.length(Cats);
          Cats = rtl.arraySetLength(Cats,"",N + 1);
          Cnt = rtl.arraySetLength(Cnt,0,N + 1);
          Cats[N] = pas.TsScenarios.EarthEvents[I].Category;
          Cnt[N] = 1;
        };
      };
      Result = '<div class="legend">';
      for (var $l2 = 0, $end2 = rtl.length(Cats) - 1; $l2 <= $end2; $l2++) {
        I = $l2;
        Result = Result + '<span><i style="background:' + pas.WebDraw.CategoryColor(Cats[I]) + '"></i>' + pas.TsScenarios.CategoryLabel(Cats[I]) + " (" + pas.SysUtils.IntToStr(Cnt[I]) + ")</span>";
      };
      Result = Result + "</div>";
      return Result;
    };
    $impl.TabDot = function (Tab) {
      var Result = "";
      var I = 0;
      var Worst = 0;
      Worst = 0;
      for (var $l = 0, $end = rtl.length(pas.WebState.A.Findings) - 1; $l <= $end; $l++) {
        I = $l;
        if ((pas.WebState.FindingTab(pas.WebState.A.Findings[I].Code) === Tab) && (pas.WebState.A.Findings[I].Sev > Worst) && (pas.WebState.A.Findings[I].Sev !== 1)) Worst = pas.WebState.A.Findings[I].Sev;
      };
      var $tmp = Worst;
      if ($tmp === 3) {
        Result = '<span class="dot bad" title="Something here must be fixed"></span>'}
       else if ($tmp === 2) {
        Result = '<span class="dot warn" title="There is a warning here"></span>'}
       else {
        Result = '<span class="dot" title="No problems here"></span>';
      };
      return Result;
    };
    $impl.TabFindings = function (Tab) {
      var Result = "";
      var I = 0;
      Result = "";
      for (var $l = 0, $end = rtl.length(pas.WebState.A.Findings) - 1; $l <= $end; $l++) {
        I = $l;
        if ((pas.WebState.FindingTab(pas.WebState.A.Findings[I].Code) === Tab) && (pas.WebState.A.Findings[I].Sev !== 0)) Result = Result + $impl.FindingHtml(pas.WebState.A.Findings[I],false);
      };
      if (Result !== "") Result = '<div style="margin-bottom:14px">' + Result + "</div>";
      return Result;
    };
    $impl.Opt = function (Sel, Off, Act, Arg, Title, Analog, Blurb, StatsHtml, Extra) {
      var Result = "";
      var Cls = "";
      Cls = "opt";
      if (Sel) Cls = Cls + " sel";
      if (Off) Cls = Cls + " off";
      Result = '<button type="button" class="' + Cls + '" data-act="' + Act + '" data-a="' + Arg + '" aria-pressed="';
      if (Sel) {
        Result = Result + 'true">'}
       else Result = Result + 'false">';
      Result = Result + '<span class="tick"></span><span class="opt-title">' + Title + "</span>";
      if (Analog !== "") Result = Result + '<span class="opt-analog">' + Analog + "</span>";
      Result = Result + '<span class="opt-blurb">' + Blurb + "</span>" + Extra;
      if (StatsHtml !== "") Result = Result + '<span class="stats">' + StatsHtml + "</span>";
      Result = Result + "</button>";
      return Result;
    };
    $impl.PartFigures = function (K, Idx, MassKg, PowerW, CostM) {
      var P = pas.TsTypes.TPart.$new();
      var Bus = pas.TsTypes.TPart.$new();
      var Risk = pas.TsTypes.TPart.$new();
      var G = 0.0;
      var GP = 0.0;
      P.$assign(pas.TsCatalog.Parts[K][Idx]);
      Bus.$assign(pas.TsCatalog.Parts[0][pas.WebState.D.Part[0]]);
      Risk.$assign(pas.TsCatalog.Parts[10][pas.WebState.D.Part[10]]);
      G = Bus.G;
      if (G >= 1) {
        GP = Math.pow(G,0.6)}
       else GP = Math.pow(G,1.1);
      MassKg.set(P.MassKg);
      PowerW.set(P.PowerW);
      CostM.set(P.CostM);
      var $tmp = K;
      if ($tmp === 0) {
        CostM.set(P.CostM * Risk.A)}
       else if ($tmp === 2) {
        MassKg.set(P.MassKg * G * Risk.B);
        PowerW.set(P.PowerW * Math.pow(G,0.8));
        CostM.set(P.CostM * Math.pow(G,0.7) * Risk.A);
      } else if ($tmp === 1) {
        MassKg.set(P.MassKg * GP);
        CostM.set(P.CostM * GP * Risk.A);
      } else if ($tmp === 5) {
        MassKg.set(P.MassKg * G);
        CostM.set(P.CostM * Math.pow(G,0.7));
      } else if ($tmp === 3) {
        CostM.set((P.CostM * Math.pow(G,0.7)) + P.E)}
       else if ($tmp === 4) {
        MassKg.set(P.MassKg * Risk.B);
        CostM.set(P.CostM * Risk.A);
      };
    };
    $impl.PartGroup = function (K, Title, Intro) {
      var Result = "";
      var I = 0;
      var P = pas.TsTypes.TPart.$new();
      var M = 0.0;
      var W = 0.0;
      var C = 0.0;
      var S = "";
      var Extra = "";
      var Off = false;
      Result = '<div class="group-title"><h3>' + Title + "</h3>" + $impl.OwnerChip(pas.TsCatalog.PartKindOwner[K]) + "</div>";
      if (Intro !== "") Result = Result + '<p class="muted small" style="margin:-4px 0 10px;max-width:74ch">' + Intro + "</p>";
      Result = Result + '<div class="opt-grid">';
      for (var $l = 0, $end = rtl.length(pas.TsCatalog.Parts[K]) - 1; $l <= $end; $l++) {
        I = $l;
        P.$assign(pas.TsCatalog.Parts[K][I]);
        $impl.PartFigures(K,I,{get: function () {
            return M;
          }, set: function (v) {
            M = v;
          }},{get: function () {
            return W;
          }, set: function (v) {
            W = v;
          }},{get: function () {
            return C;
          }, set: function (v) {
            C = v;
          }});
        S = "";
        Extra = "";
        var $tmp = K;
        if ($tmp === 0) {
          S = $impl.Stat("frame",pas.TsFmt.FmtMass(M)) + $impl.Stat("carries",pas.TsFmt.FmtMass(P.B) + ", " + pas.SysUtils.IntToStr(Math.round(P.C)) + " instr") + $impl.Stat("cost",pas.TsFmt.FmtMoney(C)) + $impl.Stat("build",pas.TsFmt.FmtYears(P.DevYears))}
         else if ($tmp === 1) {
          if (P.Tier === 0) {
            S = $impl.Stat("mass","0 kg") + $impl.Stat("cost","$0")}
           else S = $impl.Stat("efficiency",pas.TsFmt.FmtNum(P.A,0) + " s") + $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
         else if ($tmp === 9) {
          S = $impl.Stat("cost",pas.TsFmt.FmtMoney(C) + " a year")}
         else if ($tmp === 10) {
          S = $impl.Stat("cost","x" + pas.TsFmt.FmtNum(P.A,2)) + $impl.Stat("faults","x" + pas.TsFmt.FmtNum(P.C,2)) + $impl.Stat("time",$impl.Signed(P.D,pas.TsFmt.FmtNum(Math.abs(P.D),1)) + " y")}
         else if ($tmp === 11) {
          S = $impl.Stat("time","x" + pas.TsFmt.FmtNum(P.A,2)) + $impl.Stat("cost","x" + pas.TsFmt.FmtNum(P.B,2))}
         else if ($tmp === 4) {
          S = $impl.Stat("storage",pas.TsFmt.FmtData(P.A)) + $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("power",pas.TsFmt.FmtPower(W)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
         else if ($tmp === 7) {
          if (P.Tier === 4) {
            S = $impl.Stat("rate","x50 or more") + $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("power",pas.TsFmt.FmtPower(W)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
           else S = $impl.Stat("rate","x" + pas.TsFmt.FmtAuto(P.A)) + $impl.Stat("limit",pas.TsFmt.FmtRate(P.B)) + $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
         else if ($tmp === 8) {
          S = $impl.Stat("signal",pas.TsFmt.FmtNum(P.A,0) + " W") + $impl.Stat("draws",pas.TsFmt.FmtPower(W)) + $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
         else if ($tmp === 6) {
          S = $impl.Stat("mass",pas.TsFmt.FmtMass(M)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(C))}
         else {
          S = $impl.Stat("mass",pas.TsFmt.FmtMass(M));
          if (W > 0) S = S + $impl.Stat("power",pas.TsFmt.FmtPower(W));
          S = S + $impl.Stat("cost",pas.TsFmt.FmtMoney(C));
        };
        Off = (K !== 0) && (P.MinBus > pas.TsCatalog.Parts[0][pas.WebState.D.Part[0]].Tier);
        if (Off) Extra = '<span class="needs">Needs a bigger spacecraft bus</span>';
        Result = Result + $impl.Opt(pas.WebState.D.Part[K] === I,Off,"part",pas.SysUtils.IntToStr(K) + ":" + pas.SysUtils.IntToStr(I),P.Name,P.Analog,P.Blurb,S,Extra);
      };
      Result = Result + "</div>";
      return Result;
    };
    $impl.RadWord = function (L) {
      var Result = "";
      var $tmp = L;
      if ($tmp === 0) {
        Result = "gentle"}
       else if ($tmp === 1) {
        Result = "moderate"}
       else if ($tmp === 2) {
        Result = "harsh"}
       else {
        Result = "extreme";
      };
      return Result;
    };
    $impl.TabOrbit = function () {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      var O = pas.TsTypes.TOrbit.$new();
      var I = 0;
      var S = "";
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      Result = '<div class="tab-intro"><h2>Where will it work?</h2><p>The orbit decides what the instruments can see, how much fuel it takes to get there ' + "and stay there, how long the nights are and how far the radio has to shout.</p></div>" + $impl.TabFindings(0);
      if (Sc.UsesEonet) Result = Result + '<div class="map-box" style="margin-bottom:10px"><canvas id="cv-map" width="1280" height="640" role="img" ' + 'aria-label="World map of real events and what the chosen orbit can see"></canvas></div>' + $impl.EventLegend() + '<p class="small muted" style="margin:6px 0 14px">Bright dots are real events this orbit can see. Dim ones are out of reach. ' + pas.WebUtil.Chip("chip-real",pas.TsScenarios.EarthEventsSource) + "</p>";
      Result = Result + '<div class="cv-box" style="margin-bottom:14px"><canvas id="cv-orbit" width="1280" height="620" role="img" ' + 'aria-label="Animated picture of the chosen orbit"></canvas><div class="cv-cap">Grey stretches of the orbit are in shadow: no solar power there. ' + "Altitudes are squeezed to fit the picture.</div></div>";
      Result = Result + '<div class="group-title"><h3>Orbit</h3>' + $impl.OwnerChip(1) + '</div><div class="opt-grid">';
      for (var $l = 0, $end = rtl.length(Sc.Orbits) - 1; $l <= $end; $l++) {
        I = $l;
        O.$assign(Sc.Orbits[I]);
        S = $impl.Stat("to get in",pas.TsFmt.FmtDv(O.DvInsert * Sc.Transfers[pas.WebState.D.Transfer].DvFactor)) + $impl.Stat("per year",pas.TsFmt.FmtDv(O.DvPerYear)) + $impl.Stat("shadow",pas.TsFmt.FmtPct(O.EclipseFrac));
        if (O.EventsTotal > 0) {
          S = S + $impl.Stat("sees",pas.SysUtils.IntToStr(O.EventsSeen) + "/" + pas.SysUtils.IntToStr(O.EventsTotal) + " events")}
         else S = S + $impl.Stat("reach",pas.TsFmt.FmtPct(O.Coverage));
        S = S + $impl.Stat("radiation",$impl.RadWord(O.RadLevel));
        Result = Result + $impl.Opt(pas.WebState.D.Orbit === I,false,"orbit",pas.SysUtils.IntToStr(I),O.Name,O.Blurb,O.Why,S,"");
      };
      Result = Result + "</div>";
      if (rtl.length(Sc.Transfers) > 1) {
        Result = Result + '<div class="group-title"><h3>Route</h3>' + $impl.OwnerChip(1) + "</div>" + '<p class="muted small" style="margin:-4px 0 10px;max-width:74ch">A faster route needs more launch energy, so each rocket can carry less. ' + 'A slower route lets a smaller rocket do the job, if you can wait.</p><div class="opt-grid">';
        for (var $l1 = 0, $end1 = rtl.length(Sc.Transfers) - 1; $l1 <= $end1; $l1++) {
          I = $l1;
          Result = Result + $impl.Opt(pas.WebState.D.Transfer === I,false,"transfer",pas.SysUtils.IntToStr(I),Sc.Transfers[I].Name,"",Sc.Transfers[I].Blurb,$impl.Stat("launch energy",pas.TsFmt.FmtNum(Sc.Transfers[I].C3,0)) + $impl.Stat("trip",pas.TsFmt.FmtYears(Sc.Transfers[I].CruiseYears)) + $impl.Stat("braking","x" + pas.TsFmt.FmtNum(Sc.Transfers[I].DvFactor,2)),"");
        };
        Result = Result + "</div>";
      };
      return Result;
    };
    $impl.TabPayload = function () {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      var I = 0;
      var M = 0;
      var Prim = 0;
      var Ins = pas.TsTypes.TInstrument.$new();
      var S = "";
      var Chips = "";
      var Needs = "";
      var Off = false;
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      Prim = pas.TsScenarios.PrimaryMeasure(Sc);
      Result = '<div class="tab-intro"><h2>What will it measure?</h2><p>The instruments are the reason the mission exists. ' + "Each one adds science, and also mass, power draw, data to send home, cost and build time. Watch the gauges move as you choose.</p></div>" + $impl.TabFindings(1) + '<div class="panel" style="margin-bottom:14px"><div class="panel-title">' + pas.WebUtil.Icon("flask") + "<h3>Science priorities and what your payload delivers</h3></div>" + $impl.PriorityBars(true) + '<p class="small muted" style="margin-top:8px">Pale bar: how much the science team wants it. Green: how well your payload measures it from the chosen orbit (out of 100). ' + 'A second instrument for the same thing adds only half as much.</p></div><div class="opt-grid">';
      for (var $l = 0, $end = rtl.length(pas.TsCatalog.Instruments) - 1; $l <= $end; $l++) {
        I = $l;
        if (!pas.TsEngine.InstrumentOffered(pas.WebState.Scen,I)) continue;
        Ins.$assign(pas.TsCatalog.Instruments[I]);
        Chips = '<span class="mchips">';
        for (M = 0; M <= 8; M++) if ((Ins.Value[M] > 0) && (Sc.Weight[M] > 0.04)) {
          if (M === Prim) {
            Chips = Chips + '<span class="mchip key">'}
           else Chips = Chips + '<span class="mchip">';
          Chips = Chips + pas.TsTypes.MeasureName[M] + " <b>" + pas.TsFmt.FmtNum(Ins.Value[M],0) + "</b></span>";
        };
        Chips = Chips + "</span>";
        Needs = "";
        if (Ins.NeedsFinePointing) Needs = Needs + "Needs steady pointing. ";
        if (Ins.NeedsCooling) Needs = Needs + "Needs a cryocooler. ";
        if (Ins.NeedsHGA) Needs = Needs + "Needs a dish and X-band. ";
        Off = Ins.MinBus > pas.TsCatalog.Parts[0][pas.WebState.D.Part[0]].Tier;
        if (Off) Needs = Needs + "Too big for this bus. ";
        if (Needs !== "") Chips = Chips + '<span class="needs">' + Needs + "</span>";
        S = $impl.Stat("mass",pas.TsFmt.FmtMass(Ins.MassKg)) + $impl.Stat("power",pas.TsFmt.FmtPower(Ins.PowerW)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(Ins.CostM)) + $impl.Stat("data",pas.TsFmt.FmtData(Ins.DataMbps * Ins.Duty * Sc.DataScale * Sc.Orbits[pas.WebState.D.Orbit].DataFactor * 86.4) + "/day");
        Result = Result + $impl.Opt((I <= (rtl.length(pas.WebState.D.Instr) - 1)) && pas.WebState.D.Instr[I],Off,"instr",pas.SysUtils.IntToStr(I),Ins.Name,Ins.Analog,Ins.Blurb,S,Chips);
      };
      Result = Result + "</div>";
      return Result;
    };
    $impl.TabSpacecraft = function () {
      var Result = "";
      Result = '<div class="tab-intro"><h2>What will carry it?</h2><p>The bus is everything that is not an instrument: the frame, the engines, ' + "the pointing system and the protection. A bigger bus carries more, and needs more fuel and a bigger rocket to match.</p></div>" + $impl.TabFindings(2) + '<div class="ripple">Speed change needed: <b>' + pas.TsFmt.FmtDv(pas.WebState.A.DvNeed) + "</b> (" + pas.TsFmt.FmtDv(pas.WebState.A.DvInsert) + " to get into orbit, " + pas.TsFmt.FmtDv(pas.WebState.A.DvKeep) + " to stay there for " + pas.TsFmt.FmtYears(pas.WebState.D.LifeYears) + ", plus 10 % spare). With the engine chosen that takes <b>" + pas.TsFmt.FmtMass(pas.WebState.A.PropKg) + "</b> of propellant for a " + pas.TsFmt.FmtMass(pas.WebState.A.DryKg) + " spacecraft.</div>" + $impl.PartGroup(0,"Spacecraft bus","") + $impl.PartGroup(1,"Propulsion","The rocket equation rules here: every kilogram of fuel needs more fuel to carry it. An efficient engine (a high number of seconds) breaks the spiral.") + $impl.PartGroup(2,"Attitude control","How the spacecraft knows which way it faces and turns to point. Sharp cameras and narrow radio beams need a steady platform.") + $impl.PartGroup(3,"Thermal control","Space is both very hot and very cold. Electronics, fuel and detectors each have a temperature they must be kept at.") + $impl.PartGroup(5,"Radiation shielding","Added to whatever protection the computer has. Radiation here is " + $impl.RadWord(pas.TsScenarios.Scenarios[pas.WebState.Scen].Orbits[pas.WebState.D.Orbit].RadLevel) + ".");
      return Result;
    };
    $impl.PlainNum = function (X) {
      var Result = "";
      Result = pas.SysUtils.StringReplace(pas.TsFmt.FmtNum(X,2),",","",rtl.createSet(0));
      return Result;
    };
    $impl.TabPower = function () {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      var Bus = pas.TsTypes.TPart.$new();
      var Step = 0.0;
      var MaxB = 0.0;
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      Bus.$assign(pas.TsCatalog.Parts[0][pas.WebState.D.Part[0]]);
      Result = '<div class="tab-intro"><h2>What will power it?</h2><p>Sunlight fades with the square of distance, and solar panels make nothing in shadow. ' + "Size the array for the worst day, and the battery for the longest night.</p></div>" + $impl.TabFindings(3);
      var $tmp = Bus.Tier;
      if ($tmp === 0) {
        Step = 0.1;
        MaxB = 600;
      } else if ($tmp === 1) {
        Step = 0.5;
        MaxB = 4000;
      } else if ($tmp === 2) {
        Step = 1;
        MaxB = 10000;
      } else {
        Step = 2;
        MaxB = 20000;
      };
      Result = Result + '<div class="slider-row"><div class="slider-head"><div><h3>Solar array ' + $impl.OwnerChip(2) + '</h3><span class="muted small">Up to ' + pas.TsFmt.FmtNum(Bus.D,1) + " m2 on this bus. Each square metre weighs " + pas.TsFmt.FmtNum(3.4,1) + ' kg.</span></div><span class="slider-val" id="val-solar">' + pas.TsFmt.FmtNum(pas.WebState.D.SolarM2,1) + " m2</span></div>" + '<input type="range" data-in="solar" aria-label="Solar array area" min="0" max="' + $impl.PlainNum(Bus.D) + '" step="' + $impl.PlainNum(Step) + '" value="' + $impl.PlainNum(Math.min(pas.WebState.D.SolarM2,Bus.D)) + '"></div>';
      Result = Result + '<div class="slider-row"><div class="slider-head"><div><h3>Battery ' + $impl.OwnerChip(2) + '</h3><span class="muted small">Carries the spacecraft through the dark. About 7.7 kg per kilowatt-hour.</span></div>' + '<span class="slider-val" id="val-battery">' + pas.TsFmt.FmtNum(pas.WebState.D.BatteryWh,0) + " Wh</span></div>" + '<input type="range" data-in="battery" aria-label="Battery capacity" min="0" max="' + $impl.PlainNum(MaxB) + '" step="' + $impl.PlainNum(MaxB / 200) + '" value="' + $impl.PlainNum(Math.min(pas.WebState.D.BatteryWh,MaxB)) + '"></div>';
      if (Sc.AllowRTG) {
        Result = Result + '<div class="slider-row"><div class="slider-head"><div><h3>Nuclear batteries (RTG) ' + $impl.OwnerChip(2) + '</h3><span class="muted small">Each makes 110 W anywhere, day or night, for decades. Each weighs 45 kg, costs ' + pas.TsFmt.FmtMoney(95) + ' and the first one adds a year of safety approvals.</span></div><span class="stepper">' + pas.WebUtil.Btn("btn","rtg","-1","&minus;") + '<span class="slider-val">' + pas.SysUtils.IntToStr(pas.WebState.D.RtgCount) + "</span>" + pas.WebUtil.Btn("btn","rtg","1","+") + "</span></div></div>"}
       else Result = Result + '<p class="muted small" style="margin:0 0 10px">Nuclear power is not offered for this mission: there is enough sunlight, and plutonium is scarce.</p>';
      Result = Result + '<div class="panel" id="power-info">' + $mod.PowerInfo() + "</div>";
      return Result;
    };
    $impl.TabComms = function () {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      var Dist = 0.0;
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      if (Sc.NearEarth) {
        Dist = Sc.Orbits[pas.WebState.D.Orbit].RangeKm}
       else Dist = ((Sc.EarthMinAU + Sc.EarthMaxAU) / 2) * 1.495978707E8;
      Result = '<div class="tab-intro"><h2>How will the data get home?</h2><p>Data that never reaches Earth is science that never happened. ' + "The rate grows with dish size, transmitter power and frequency, and falls with the square of distance.</p></div>" + $impl.TabFindings(4) + '<div class="panel" style="margin-bottom:6px"><div class="numgrid">' + $impl.Num(pas.TsFmt.FmtDist(Dist),"to the ground station") + $impl.Num(pas.TsFmt.FmtRate(pas.WebState.A.RateAvgMbps),"typical data rate") + $impl.Num(pas.TsFmt.FmtRate(pas.WebState.A.RateMinMbps),"when furthest away") + $impl.Num(pas.TsFmt.FmtNum(pas.WebState.A.ContactHr,1) + " h","of contact a day") + $impl.Num(pas.TsFmt.FmtData(pas.WebState.A.GenGbitDay),"recorded a day") + $impl.Num(pas.TsFmt.FmtData(pas.WebState.A.DownGbitDay),"can be sent a day") + $impl.Num(pas.TsFmt.FmtPct(pas.WebState.A.DataReturn),"of the data gets home") + "</div></div>" + $impl.PartGroup(6,"Antenna","Doubling the dish width gives four times the data rate.") + $impl.PartGroup(7,"Radio band","") + $impl.PartGroup(8,"Transmitter","") + $impl.PartGroup(9,"Ground network","Antennas on Earth are shared between missions. More listening time costs more every year.") + $impl.PartGroup(4,"Flight computer and recorder","The recorder holds data between contacts. The computer also has to survive the radiation.");
      return Result;
    };
    $impl.TabLaunch = function () {
      var Result = "";
      var I = 0;
      var K = 0;
      var N = 0;
      var Opts = [];
      var Order = [];
      var L = pas.TsTypes.TLauncher.$new();
      var S = "";
      var Extra = "";
      var Tone = "";
      var T = 0;
      var Better = false;
      Result = '<div class="tab-intro"><h2>What will lift it?</h2><p>Fuelled, your spacecraft weighs <b>' + pas.TsFmt.FmtMass(pas.WebState.A.WetKg) + "</b> and has to reach " + pas.TsEngine.LaunchTargetName(pas.WebState.D) + ". Every rocket can lift less the harder it has to throw.</p></div>" + $impl.TabFindings(5);
      N = rtl.length(pas.TsCatalog.Launchers);
      Opts = rtl.arraySetLength(Opts,pas.TsEngine.TLaunchOption,N);
      Order = rtl.arraySetLength(Order,0,N);
      for (var $l = 0, $end = N - 1; $l <= $end; $l++) {
        I = $l;
        Opts[I].$assign(pas.TsEngine.LaunchOption(I,pas.WebState.D,pas.WebState.A.WetKg));
        Order[I] = I;
      };
      for (var $l1 = 0, $end1 = N - 2; $l1 <= $end1; $l1++) {
        I = $l1;
        for (var $l2 = I + 1, $end2 = N - 1; $l2 <= $end2; $l2++) {
          K = $l2;
          Better = false;
          if (Opts[Order[K]].Fits && !Opts[Order[I]].Fits) {
            Better = true}
           else if (Opts[Order[K]].Fits === Opts[Order[I]].Fits) {
            if (Opts[Order[K]].CanReach && !Opts[Order[I]].CanReach) {
              Better = true}
             else if ((Opts[Order[K]].CanReach === Opts[Order[I]].CanReach) && (Opts[Order[K]].CostM < Opts[Order[I]].CostM)) Better = true;
          };
          if (Better) {
            T = Order[I];
            Order[I] = Order[K];
            Order[K] = T;
          };
        };
      };
      Result = Result + '<div class="group-title"><h3>Launch vehicle</h3>' + $impl.OwnerChip(0) + '</div><div class="opt-grid">';
      for (var $l3 = 0, $end3 = N - 1; $l3 <= $end3; $l3++) {
        K = $l3;
        I = Order[K];
        L.$assign(pas.TsCatalog.Launchers[I]);
        Extra = "";
        if (!Opts[I].CanReach) {
          S = $impl.Stat("cost",pas.TsFmt.FmtMoney(Opts[I].CostM));
          Extra = '<span class="needs">' + Opts[I].Why + "</span>";
        } else {
          S = $impl.Stat("can lift",pas.TsFmt.FmtMass(Opts[I].CapKg)) + $impl.Stat("cost",pas.TsFmt.FmtMoney(Opts[I].CostM)) + $impl.Stat("success",pas.TsFmt.FmtPct(L.Reliability));
          if (Opts[I].Fits) {
            Tone = "good";
            if (Opts[I].Margin < 0.1) Tone = "warn";
            Extra = '<span class="gauge-bar" style="display:block"><span class="gauge-fill ' + Tone + '" style="display:block;width:' + pas.TsFmt.FmtNum(pas.TsTypes.Clamp(1 - Opts[I].Margin,0,1) * 100,0) + '%"></span></span><span class="tiny muted">' + pas.TsFmt.FmtPct(Opts[I].Margin) + " to spare</span>";
          } else Extra = '<span class="needs">Too small: ' + pas.TsFmt.FmtMass(pas.WebState.A.WetKg - Opts[I].CapKg) + " over its limit.</span>";
        };
        Result = Result + $impl.Opt(pas.WebState.D.Launcher === I,!Opts[I].Fits,"launcher",pas.SysUtils.IntToStr(I),L.Name,L.Agency,L.Blurb,S,Extra);
      };
      Result = Result + "</div>";
      return Result;
    };
    $impl.TabPlan = function () {
      var Result = "";
      var Sc = pas.TsTypes.TScenario.$new();
      Sc.$assign(pas.TsScenarios.Scenarios[pas.WebState.Scen]);
      Result = '<div class="tab-intro"><h2>How will it be run?</h2><p>Time, money and risk are resources too. A longer mission returns more science, ' + "with diminishing returns, and costs more to operate. Reserves and backups look like waste until the day they are needed.</p></div>" + $impl.TabFindings(6) + '<div class="slider-row"><div class="slider-head"><div><h3>Planned science operations ' + $impl.OwnerChip(3) + '</h3><span class="muted small">At least ' + pas.TsFmt.FmtYears(Sc.MinLife) + ". Each year costs " + pas.TsFmt.FmtMoney(pas.WebState.A.OpsPerYearM) + " to operate and uses station-keeping fuel.</span></div>" + '<span class="slider-val" id="val-life">' + pas.TsFmt.FmtYears(pas.WebState.D.LifeYears) + "</span></div>" + '<input type="range" data-in="life" aria-label="Planned science operations in years" min="0.25" max="' + $impl.PlainNum(Sc.MaxLife) + '" step="0.25" value="' + $impl.PlainNum(pas.WebState.D.LifeYears) + '"></div>' + '<div class="slider-row"><div class="slider-head"><div><h3>Reserves ' + $impl.OwnerChip(0) + '</h3><span class="muted small">Money held back for surprises during development. ' + 'Unspent reserves are not counted against you.</span></div><span class="slider-val" id="val-reserve">' + pas.TsFmt.FmtNum(pas.WebState.D.ReservePct,0) + " %</span></div>" + '<input type="range" data-in="reserve" aria-label="Reserves in percent" min="0" max="40" step="5" value="' + $impl.PlainNum(pas.WebState.D.ReservePct) + '"></div>' + '<div class="panel" id="plan-info">' + $mod.PlanInfo() + "</div>" + $impl.PartGroup(10,"Risk posture","NASA grades missions from class A (must not fail) to class D (cheap, higher risk accepted). More backups and testing cost money, mass and time.") + $impl.PartGroup(11,"Schedule","");
      return Result;
    };
    $impl.RippleText = function () {
      var Result = "";
      var S = "";
      Result = "";
      if (!pas.WebState.HasPrev) return Result;
      S = "";
      if (Math.abs(pas.WebState.A.DryKg - pas.WebState.PrevA.DryKg) > 0.05) S = S + $impl.Signed(pas.WebState.A.DryKg - pas.WebState.PrevA.DryKg,pas.TsFmt.FmtMass(Math.abs(pas.WebState.A.DryKg - pas.WebState.PrevA.DryKg))) + " equipment";
      if (Math.abs(pas.WebState.A.PropKg - pas.WebState.PrevA.PropKg) > 0.05) {
        if (S !== "") S = S + " &rarr; ";
        S = S + $impl.Signed(pas.WebState.A.PropKg - pas.WebState.PrevA.PropKg,pas.TsFmt.FmtMass(Math.abs(pas.WebState.A.PropKg - pas.WebState.PrevA.PropKg))) + " propellant";
      };
      if ((pas.WebState.A.LvCapKg > 0) && (pas.WebState.PrevA.LvCapKg > 0) && (Math.abs(pas.WebState.A.MassMargin - pas.WebState.PrevA.MassMargin) > 0.004)) {
        if (S !== "") S = S + " &rarr; ";
        S = S + "launch margin " + pas.TsFmt.FmtPct(pas.WebState.PrevA.MassMargin) + " to " + pas.TsFmt.FmtPct(pas.WebState.A.MassMargin);
      };
      if (Math.abs(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW) > 0.5) {
        if (S !== "") S = S + "; ";
        S = S + $impl.Signed(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW,pas.TsFmt.FmtPower(Math.abs(pas.WebState.A.LoadAvgW - pas.WebState.PrevA.LoadAvgW))) + " power needed";
      };
      if (Math.abs(pas.WebState.A.DataReturn - pas.WebState.PrevA.DataReturn) > 0.004) {
        if (S !== "") S = S + "; ";
        S = S + "data home " + pas.TsFmt.FmtPct(pas.WebState.PrevA.DataReturn) + " to " + pas.TsFmt.FmtPct(pas.WebState.A.DataReturn);
      };
      if (Math.abs(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal) > 0.05) {
        if (S !== "") S = S + "; ";
        S = S + $impl.Signed(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal,pas.TsFmt.FmtMoney(Math.abs(pas.WebState.A.CostTotal - pas.WebState.PrevA.CostTotal)));
      };
      if (Math.abs(pas.WebState.A.SciencePct - pas.WebState.PrevA.SciencePct) > 0.5) {
        if (S !== "") S = S + "; ";
        S = S + "science " + pas.TsFmt.FmtNum(pas.WebState.PrevA.SciencePct,0) + " % to " + pas.TsFmt.FmtNum(pas.WebState.A.SciencePct,0) + " %";
      };
      if (S !== "") Result = '<div class="ripple"><b>Your last change rippled:</b> ' + S + "</div>";
      return Result;
    };
    $impl.WhenText = function (E) {
      var Result = "";
      var $tmp = E.Phase;
      if ($tmp === 0) {
        Result = "Development"}
       else if ($tmp === 1) {
        Result = "Launch day"}
       else if ($tmp === 2) {
        Result = "Cruise, week " + pas.SysUtils.IntToStr(E.Week)}
       else if ($tmp === 3) {
        Result = "Arrival"}
       else {
        Result = "Week " + pas.SysUtils.IntToStr(E.Week);
      };
      return Result;
    };
    $impl.SBar = function (AName, V, Weight) {
      var Result = "";
      Result = '<div class="sbar"><span>' + AName + ' <span class="muted tiny">' + pas.TsFmt.FmtPct(Weight) + '</span></span><div class="sbar-track"><div class="sbar-fill" style="width:' + pas.TsFmt.FmtNum(pas.TsTypes.Clamp(V,0,100),0) + '%"></div></div><span class="mono">' + pas.TsFmt.FmtNum(V,0) + "</span></div>";
      return Result;
    };
    $impl.ModalShell = function (Title, Body, Wide) {
      var Result = "";
      Result = '<div class="modal';
      if (Wide) Result = Result + " wide";
      Result = Result + '" role="dialog" aria-modal="true" aria-label="' + Title + '"><div class="modal-head"><h2>' + Title + "</h2>" + pas.WebUtil.Btn("btn btn-ghost btn-small","close","",pas.WebUtil.Icon("x") + "Close") + "</div>" + Body + "</div>";
      return Result;
    };
    $impl.LinesTable = function (L, Head, UnitName, Dec) {
      var Result = "";
      var I = 0;
      var Sum = 0.0;
      Sum = 0;
      Result = '<table class="tbl"><tr><th>' + Head + '</th><th class="n">' + UnitName + "</th></tr>";
      for (var $l = 0, $end = rtl.length(L) - 1; $l <= $end; $l++) {
        I = $l;
        Result = Result + "<tr><td>" + L[I].Name + '</td><td class="n">' + pas.TsFmt.FmtNum(L[I].Value,Dec) + "</td></tr>";
        Sum = Sum + L[I].Value;
      };
      Result = Result + '<tr><td><b>Total</b></td><td class="n"><b>' + pas.TsFmt.FmtNum(Sum,Dec) + "</b></td></tr></table>";
      return Result;
    };
  };
},["strutils","WebUtil","WebState","WebStore","WebNasa","WebDraw","TsFmt","TsCatalog","TsScenarios","TsEngine","TsSim","TsScore"]);
rtl.module("TsExamples",["System","TsTypes"],function () {
  "use strict";
  var $mod = this;
  var $impl = $mod.$impl;
  this.ExampleDesign = function (AScenario, ADifficulty, ASandbox) {
    var Result = pas.TsTypes.TDesign.$new();
    var D = pas.TsTypes.TDesign.$new();
    var Id = "";
    D.$assign(pas.TsEngine.NewDesign(AScenario,ADifficulty,ASandbox));
    Id = pas.TsScenarios.Scenarios[AScenario].Id;
    if (Id === "earth") {
      $impl.Pick(D,"tir");
      $impl.Pick(D,"radiometer");
      $impl.Orbit(D,"sso");
      $impl.Use(D,0,"small");
      $impl.Use(D,1,"mono");
      $impl.Use(D,2,"rw3");
      $impl.Use(D,4,"radtol");
      $impl.Use(D,6,"patch");
      $impl.Use(D,7,"x");
      $impl.Use(D,8,"tx5");
      $impl.Use(D,9,"standard");
      D.SolarM2 = 1.0;
      D.BatteryWh = 250;
      D.LifeYears = 3;
      D.ReservePct = 20;
      D.Launcher = pas.TsCatalog.FindLauncher("rideshare");
    } else if (Id === "moon") {
      $impl.Pick(D,"neutron");
      $impl.Pick(D,"tir");
      $impl.Orbit(D,"frozen");
      $impl.Route(D,"direct");
      $impl.Use(D,0,"small");
      $impl.Use(D,1,"mono");
      $impl.Use(D,2,"rw3");
      $impl.Use(D,4,"radtol");
      $impl.Use(D,6,"dish06");
      $impl.Use(D,7,"x");
      $impl.Use(D,8,"tx5");
      $impl.Use(D,9,"basic");
      D.SolarM2 = 1.5;
      D.BatteryWh = 350;
      D.LifeYears = 2;
      D.ReservePct = 20;
      D.Launcher = pas.TsCatalog.FindLauncher("rideshare");
    } else if (Id === "mars") {
      $impl.Pick(D,"radiometer");
      $impl.Pick(D,"cam_ctx");
      $impl.Pick(D,"tir");
      $impl.Pick(D,"relay");
      $impl.Orbit(D,"low_aero");
      $impl.Use(D,0,"medium");
      $impl.Use(D,1,"biprop");
      $impl.Use(D,2,"rw3");
      $impl.Use(D,3,"passive");
      $impl.Use(D,4,"radhard");
      $impl.Use(D,6,"dish20");
      $impl.Use(D,7,"x");
      $impl.Use(D,8,"tx100");
      $impl.Use(D,9,"standard");
      D.SolarM2 = 10;
      D.BatteryWh = 800;
      D.LifeYears = 2;
      D.ReservePct = 20;
      D.Launcher = pas.TsCatalog.FindLauncher("lvm3");
    } else if (Id === "apophis") {
      $impl.Pick(D,"tir");
      $impl.Orbit(D,"rdv");
      $impl.Route(D,"fast");
      $impl.Use(D,0,"cube");
      $impl.Use(D,1,"sep");
      $impl.Use(D,2,"rw3");
      $impl.Use(D,4,"radtol");
      $impl.Use(D,6,"dish06");
      $impl.Use(D,7,"x");
      $impl.Use(D,8,"tx20");
      $impl.Use(D,9,"standard");
      $impl.Use(D,11,"fast");
      D.SolarM2 = 1.0;
      D.BatteryWh = 140;
      D.LifeYears = 1;
      D.ReservePct = 20;
      D.Launcher = pas.TsCatalog.FindLauncher("pslv");
    } else {
      $impl.Pick(D,"sar");
      $impl.Pick(D,"mag");
      $impl.Pick(D,"cam_ctx");
      $impl.Pick(D,"tir");
      $impl.Orbit(D,"tour");
      $impl.Route(D,"veega");
      $impl.Use(D,0,"medium");
      $impl.Use(D,1,"biprop");
      $impl.Use(D,2,"rw3");
      $impl.Use(D,3,"active");
      $impl.Use(D,4,"radhard");
      $impl.Use(D,5,"spot");
      $impl.Use(D,6,"dish30");
      $impl.Use(D,7,"x");
      $impl.Use(D,8,"tx100");
      $impl.Use(D,9,"premium");
      D.SolarM2 = 0;
      D.RtgCount = 5;
      D.BatteryWh = 1500;
      D.LifeYears = 3.5;
      D.ReservePct = 20;
      D.Launcher = pas.TsCatalog.FindLauncher("falcon9");
    };
    Result.$assign(D);
    return Result;
  };
  $mod.$implcode = function () {
    $impl.Pick = function (D, Id) {
      var I = 0;
      I = pas.TsCatalog.FindInstrument(Id);
      if ((I >= 0) && (I <= (rtl.length(D.Instr) - 1))) D.Instr[I] = true;
    };
    $impl.Use = function (D, K, Id) {
      var I = 0;
      I = pas.TsCatalog.FindPart(K,Id);
      if (I >= 0) D.Part[K] = I;
    };
    $impl.Orbit = function (D, Id) {
      var I = 0;
      for (var $l = 0, $end = rtl.length(pas.TsScenarios.Scenarios[D.Scenario].Orbits) - 1; $l <= $end; $l++) {
        I = $l;
        if (pas.TsScenarios.Scenarios[D.Scenario].Orbits[I].Id === Id) D.Orbit = I;
      };
    };
    $impl.Route = function (D, Id) {
      var I = 0;
      for (var $l = 0, $end = rtl.length(pas.TsScenarios.Scenarios[D.Scenario].Transfers) - 1; $l <= $end; $l++) {
        I = $l;
        if (pas.TsScenarios.Scenarios[D.Scenario].Transfers[I].Id === Id) D.Transfer = I;
      };
    };
  };
},["TsCatalog","TsScenarios","TsEngine"]);
rtl.module("WebApp",["System","JS","Web","SysUtils","Math","TsTypes"],function () {
  "use strict";
  var $mod = this;
  rtl.createClass(this,"TGame",pas.System.TObject,function () {
    this.$init = function () {
      pas.System.TObject.$init.call(this);
      this.FRunning = false;
      this.FSpeed = 0;
      this.FLaunching = false;
      this.FLaunchT0 = 0.0;
      this.FLaunchFail = false;
      this.FLaunchSize = 0;
      this.FShownLog = 0;
      this.FAccum = 0.0;
      this.FLastMs = 0.0;
      this.FTick = 0;
      this.FModalKind = "";
      this.FMissionDone = false;
      this.FKeepSeed = false;
      this.FShareUrl = "";
    };
    this.OnClick = function (Ev) {
      var Result = false;
      var T = null;
      Result = true;
      if (!rtl.isExt(Ev.target,Element)) return Result;
      T = Ev.target.closest("[data-act]");
      if (T === null) {
        if ((this.FModalKind === "info") && (Ev.target.id === "modal")) this.CloseModal();
        return Result;
      };
      if (T.hasAttribute("disabled")) return Result;
      if (T.hasAttribute("data-a")) {
        this.DoAction(T.getAttribute("data-act"),T.getAttribute("data-a"))}
       else this.DoAction(T.getAttribute("data-act"),"");
      return Result;
    };
    this.OnInput = function (Ev) {
      var Result = false;
      var T = null;
      var Name = "";
      var V = 0.0;
      var I = 0;
      Result = true;
      if (!rtl.isExt(Ev.target,Element)) return Result;
      if (!Ev.target.hasAttribute("data-in")) return Result;
      T = Ev.target;
      Name = T.getAttribute("data-in");
      if (Name === "pname") {
        I = pas.SysUtils.StrToIntDef(T.getAttribute("data-a"),0);
        if ((I >= 0) && (I <= 3)) {
          pas.WebState.PlayerName[I] = pas.SysUtils.Trim(T.value);
          if (pas.WebState.PlayerName[I] === "") pas.WebState.PlayerName[I] = "Player " + pas.SysUtils.IntToStr(I + 1);
          pas.WebStore.SaveSetting("player" + pas.SysUtils.IntToStr(I),pas.WebState.PlayerName[I]);
        };
        return Result;
      };
      if ((Name === "sandbox") || !pas.WebState.HasDesign) return Result;
      V = pas.TsFmt.ParseFloat(T.value);
      if (Name === "solar") {
        pas.WebState.D.SolarM2 = V;
        pas.WebUtil.SetText("val-solar",pas.TsFmt.FmtNum(V,1) + " m2");
      } else if (Name === "battery") {
        pas.WebState.D.BatteryWh = V;
        pas.WebUtil.SetText("val-battery",pas.TsFmt.FmtNum(V,0) + " Wh");
      } else if (Name === "life") {
        pas.WebState.D.LifeYears = V;
        pas.WebUtil.SetText("val-life",pas.TsFmt.FmtYears(V));
      } else if (Name === "reserve") {
        pas.WebState.D.ReservePct = V;
        pas.WebUtil.SetText("val-reserve",pas.TsFmt.FmtNum(V,0) + " %");
      } else return Result;
      pas.WebState.Recalc();
      pas.WebUtil.SetHtml("power-info",pas.WebViews.PowerInfo());
      pas.WebUtil.SetHtml("plan-info",pas.WebViews.PlanInfo());
      this.RenderLab(false);
      return Result;
    };
    this.OnChange = function (Ev) {
      var Result = false;
      var T = null;
      var Name = "";
      Result = true;
      if (!rtl.isExt(Ev.target,Element)) return Result;
      if (!Ev.target.hasAttribute("data-in")) return Result;
      T = Ev.target;
      Name = T.getAttribute("data-in");
      if (Name === "sandbox") {
        pas.WebState.Sandbox = T.checked;
        this.Render();
      } else if ((Name === "solar") || (Name === "battery") || (Name === "life") || (Name === "reserve")) this.RenderLab(true);
      return Result;
    };
    this.OnKey = function (Ev) {
      var Result = false;
      var K = "";
      Result = true;
      K = Ev.key;
      if ((K === "Escape") && (this.FModalKind === "info")) this.CloseModal();
      return Result;
    };
    this.OnResize = function (Ev) {
      var Result = false;
      Result = true;
      pas.WebDraw.DrawStars();
      return Result;
    };
    this.Frame = function (aTime) {
      var Ctx = null;
      this.FTick += 1;
      if ((pas.WebState.Screen === 3) && pas.WebState.HasDesign && pas.WebDraw.Prep("cv-orbit",640,310,{get: function () {
          return Ctx;
        }, set: function (v) {
          Ctx = v;
        }})) pas.WebDraw.DrawOrbitView(Ctx,640,310,pas.WebState.D,aTime / 1000);
      if ((this.FTick % 50) === 0) this.DrawStatics();
      if ((pas.WebState.Screen === 5) && pas.WebState.HasSim) this.MissionFrame(aTime);
      window.requestAnimationFrame(rtl.createCallback(this,"Frame"));
    };
    this.MissionFrame = function (Ms) {
      var Ctx = null;
      var Dt = 0.0;
      var Lt = 0.0;
      var EndT = 0.0;
      var Rate = 0.0;
      var Guard = 0;
      Dt = (Ms - this.FLastMs) / 1000;
      this.FLastMs = Ms;
      if ((Dt < 0) || (Dt > 0.25)) Dt = 0.25;
      if (this.FLaunching) {
        Lt = (pas.WebUtil.NowMs() - this.FLaunchT0) / 1000;
        if (pas.WebDraw.Prep("cv-main",640,360,{get: function () {
            return Ctx;
          }, set: function (v) {
            Ctx = v;
          }})) pas.WebDraw.DrawLaunch(Ctx,640,360,Lt,this.FLaunchSize,this.FLaunchFail);
        EndT = 15;
        if (this.FLaunchFail) EndT = 10.5;
        if (Lt >= EndT) this.EndLaunch();
        return;
      };
      if (pas.WebDraw.Prep("cv-main",640,360,{get: function () {
          return Ctx;
        }, set: function (v) {
          Ctx = v;
        }})) {
        if (pas.WebState.Sim.LostAtLaunch) {
          pas.WebDraw.DrawLaunch(Ctx,640,360,10.4,this.FLaunchSize,true)}
         else if ((pas.WebState.Sim.Phase === 0) || (pas.WebState.Sim.Phase === 1)) {
          pas.WebDraw.DrawCraft(Ctx,640,360,pas.WebState.D,pas.WebState.Sim.A);
          Ctx.font = "bold 15px ui-monospace, Consolas, monospace";
          Ctx.fillStyle = "#e8eef9";
          Ctx.textAlign = "center";
          Ctx.fillText("IN THE CLEAN ROOM: BUILDING AND TESTING",320,344);
        } else if ((pas.WebState.Sim.Phase === 2) || ((pas.WebState.Sim.Phase === 5) && (pas.WebState.Sim.SciWeek === 0) && !pas.WebState.Sim.LostAtArrival && (pas.WebState.Sim.CruiseWeeks > 0))) {
          pas.WebDraw.DrawCruise(Ctx,640,360,pas.WebState.Sim,Ms / 1000)}
         else pas.WebDraw.DrawOrbitView(Ctx,640,360,pas.WebState.D,Ms / 1000);
      };
      if (this.FRunning && pas.WebState.HasSim && !pas.WebState.Sim.HasPending && (this.FModalKind === "") && (pas.WebState.Sim.Phase !== 5)) {
        var $tmp = pas.WebState.Sim.Phase;
        if (($tmp === 0) || ($tmp === 1) || ($tmp === 3)) {
          Rate = 0.9 * this.FSpeed}
         else if ($tmp === 2) {
          var $tmp1 = this.FSpeed;
          if ($tmp1 === 1) {
            Rate = 5}
           else if ($tmp1 === 2) {
            Rate = 14}
           else {
            Rate = 40;
          };
        } else {
          var $tmp2 = this.FSpeed;
          if ($tmp2 === 1) {
            Rate = 6}
           else if ($tmp2 === 2) {
            Rate = 20}
           else {
            Rate = 70;
          };
        };
        this.FAccum = this.FAccum + (Dt * Rate);
        Guard = 0;
        while ((this.FAccum >= 1) && (Guard < 8)) {
          this.FAccum = this.FAccum - 1;
          Guard += 1;
          this.StepSim();
          if (pas.WebState.Sim.HasPending || this.FLaunching || (pas.WebState.Sim.Phase === 5) || (this.FModalKind !== "")) {
            this.FAccum = 0;
            break;
          };
        };
      };
    };
    this.Render = function () {
      var Html = "";
      var $tmp = pas.WebState.Screen;
      if ($tmp === 0) {
        Html = pas.WebViews.ViewTitle()}
       else if ($tmp === 1) {
        Html = pas.WebViews.ViewSetup()}
       else if ($tmp === 2) {
        Html = pas.WebViews.ViewBrief()}
       else if ($tmp === 3) {
        Html = pas.WebViews.ViewLab()}
       else if ($tmp === 4) {
        Html = pas.WebViews.ViewReview()}
       else if ($tmp === 5) {
        Html = pas.WebViews.ViewMission()}
       else if ($tmp === 6) {
        Html = pas.WebViews.ViewReport()}
       else {
        Html = pas.WebViews.ViewLog();
      };
      pas.WebUtil.SetHtml("app",Html);
      if (pas.WebState.Screen === 5) {
        this.FShownLog = 0;
        pas.WebUtil.SetHtml("m-log","");
        if (!this.FLaunching) this.SyncLog();
        this.SetControls();
        this.RefreshMission();
      };
      this.DrawStatics();
    };
    this.RenderLab = function (WithMain) {
      pas.WebUtil.SetHtml("lab-nav",pas.WebViews.ViewLabNav());
      if (WithMain) pas.WebUtil.SetHtml("lab-main",pas.WebViews.ViewLabMain());
      pas.WebUtil.SetHtml("lab-dash",pas.WebViews.ViewLabDash());
      this.DrawStatics();
    };
    this.DrawStatics = function () {
      var Ctx = null;
      if (pas.WebDraw.Prep("cv-map",640,320,{get: function () {
          return Ctx;
        }, set: function (v) {
          Ctx = v;
        }})) pas.WebDraw.DrawEarthMap(Ctx,640,320,pas.WebState.D,(pas.WebState.Screen === 3) && pas.WebState.HasDesign);
      if ((pas.WebState.Screen === 3) && pas.WebDraw.Prep("cv-craft",340,230,{get: function () {
          return Ctx;
        }, set: function (v) {
          Ctx = v;
        }})) pas.WebDraw.DrawCraft(Ctx,340,230,pas.WebState.D,pas.WebState.A);
      if (pas.WebState.HasSim && pas.WebDraw.Prep("cv-chart",640,170,{get: function () {
          return Ctx;
        }, set: function (v) {
          Ctx = v;
        }})) pas.WebDraw.DrawChart(Ctx,640,170,pas.WebState.Sim);
    };
    this.OpenModal = function (Html, Kind) {
      var M = null;
      M = pas.WebUtil.El("modal");
      if (M === null) return;
      M.innerHTML = Html;
      M.hidden = false;
      this.FModalKind = Kind;
    };
    this.CloseModal = function () {
      var M = null;
      M = pas.WebUtil.El("modal");
      if (M !== null) {
        M.hidden = true;
        M.innerHTML = "";
      };
      this.FModalKind = "";
    };
    this.Go = function (S) {
      pas.WebState.Screen = S;
      this.Render();
      pas.WebUtil.ScrollTop();
    };
    this.DoAction = function (Act, Arg) {
      var N = 0;
      var K = 0;
      var I = 0;
      var P = 0;
      var L = [];
      N = pas.SysUtils.StrToIntDef(Arg,0);
      if (Act === "home") {
        this.CloseModal();
        this.FRunning = false;
        this.FLaunching = false;
        this.Go(0);
      } else if (Act === "start") {
        this.FRunning = false;
        this.FLaunching = false;
        this.Go(1);
      } else if (Act === "scen") {
        if ((N >= 0) && (N <= (rtl.length(pas.TsScenarios.Scenarios) - 1))) pas.WebState.Scen = N;
        this.Render();
      } else if (Act === "diff") {
        if ((N >= 0) && (N <= 2)) pas.WebState.Difficulty = N;
        pas.WebStore.SaveSetting("difficulty",pas.SysUtils.IntToStr(N));
        this.Render();
      } else if (Act === "players") {
        if ((N >= 1) && (N <= 4)) pas.WebState.Players = N;
        this.Render();
      } else if (Act === "brief") {
        this.Go(2)}
       else if (Act === "lab") {
        this.EnterLab()}
       else if ((Act === "backlab") || (Act === "improve")) {
        this.FRunning = false;
        pas.WebState.HasPrev = false;
        pas.WebState.SharedNote = "";
        this.Go(3);
      } else if (Act === "review") {
        pas.WebState.ResetVotes();
        this.Go(4);
      } else if (Act === "vote") {
        if ((N >= 0) && (N <= pas.TsTypes.TRole.roOps)) pas.WebState.Votes[N] = !pas.WebState.Votes[N];
        this.Render();
      } else if ((Act === "fly") || (Act === "refly")) {
        this.StartMission()}
       else if (Act === "report") {
        this.Go(6)}
       else if (Act === "log") {
        this.FRunning = false;
        this.Go(7);
      } else if (Act === "loadlog") {
        L = pas.WebStore.LoadLog();
        if ((N >= 0) && (N <= (rtl.length(L) - 1))) {
          this.UseDesign(L[N].Code,"A design from your mission log was loaded.");
          this.Go(3);
        };
      } else if (Act === "clearlog") {
        if (window.confirm("Delete every mission in the log on this device?")) {
          pas.WebStore.ClearLog();
          this.Render();
        };
      } else if (Act === "tab") {
        if ((N >= 0) && (N < 7)) pas.WebState.LabTab = N;
        pas.WebState.HasPrev = false;
        this.RenderLab(true);
        pas.WebUtil.ScrollTop();
      } else if (Act === "orbit") {
        if ((N >= 0) && (N <= (rtl.length(pas.TsScenarios.Scenarios[pas.WebState.Scen].Orbits) - 1))) pas.WebState.D.Orbit = N;
        pas.WebState.Recalc();
        this.RenderLab(true);
      } else if (Act === "transfer") {
        if ((N >= 0) && (N <= (rtl.length(pas.TsScenarios.Scenarios[pas.WebState.Scen].Transfers) - 1))) pas.WebState.D.Transfer = N;
        pas.WebState.Recalc();
        this.RenderLab(true);
      } else if (Act === "instr") {
        if ((N >= 0) && (N <= (rtl.length(pas.WebState.D.Instr) - 1))) pas.WebState.D.Instr[N] = !pas.WebState.D.Instr[N];
        pas.WebState.Recalc();
        this.RenderLab(true);
      } else if (Act === "part") {
        P = pas.System.Pos(":",Arg);
        if (P > 0) {
          K = pas.SysUtils.StrToIntDef(pas.System.Copy(Arg,1,P - 1),-1);
          I = pas.SysUtils.StrToIntDef(pas.System.Copy(Arg,P + 1,10),-1);
          if ((K >= 0) && (K <= pas.TsTypes.TPartKind.pkSchedule) && (I >= 0) && (I <= (rtl.length(pas.TsCatalog.Parts[K]) - 1))) {
            pas.WebState.D.Part[K] = I;
            pas.WebState.Recalc();
            this.RenderLab(true);
          };
        };
      } else if (Act === "launcher") {
        if ((N >= 0) && (N <= (rtl.length(pas.TsCatalog.Launchers) - 1))) {
          if (pas.WebState.D.Launcher === N) {
            pas.WebState.D.Launcher = -1}
           else pas.WebState.D.Launcher = N;
        };
        pas.WebState.Recalc();
        this.RenderLab(true);
      } else if (Act === "rtg") {
        pas.WebState.D.RtgCount = pas.WebState.D.RtgCount + N;
        if (pas.WebState.D.RtgCount < 0) pas.WebState.D.RtgCount = 0;
        if (pas.WebState.D.RtgCount > 5) pas.WebState.D.RtgCount = 5;
        pas.WebState.Recalc();
        this.RenderLab(true);
      } else if (Act === "example") {
        pas.WebState.D.$assign(pas.TsExamples.ExampleDesign(pas.WebState.Scen,pas.WebState.Difficulty,pas.WebState.Sandbox));
        pas.WebState.HasDesign = false;
        pas.WebState.HasPrev = false;
        pas.WebState.Recalc();
        pas.WebState.HasPrev = false;
        this.FKeepSeed = false;
        pas.WebState.SharedNote = "An example design was loaded. It passes the review board, but it is far from the best. Can you beat it?";
        this.Render();
      } else if (Act === "share") {
        this.ShareDesign()}
       else if (Act === "copyshare") {
        try {
          window.navigator.clipboard.writeText(this.FShareUrl);
          pas.WebUtil.Toast("Link copied.");
        } catch ($e) {
          pas.WebUtil.Toast("Select the link and copy it by hand.");
        };
      } else if (Act === "gauge") {
        this.OpenModal(pas.WebViews.ModalBreakdown(Arg),"info")}
       else if (Act === "help") {
        this.OpenModal(pas.WebViews.ModalHelp(),"info")}
       else if (Act === "glossary") {
        this.OpenModal(pas.WebViews.ModalGlossary(),"info")}
       else if (Act === "about") {
        this.OpenModal(pas.WebViews.ModalAbout(),"info")}
       else if (Act === "close") {
        this.CloseModal()}
       else if (Act === "play") {
        this.FRunning = true;
        this.SetControls();
      } else if (Act === "pause") {
        this.FRunning = false;
        this.SetControls();
      } else if (Act === "speed") {
        if ((N >= 1) && (N <= 3)) this.FSpeed = N;
        this.FRunning = true;
        this.SetControls();
      } else if (Act === "skiplaunch") {
        this.EndLaunch()}
       else if (Act === "choose") {
        if (pas.WebState.HasSim && pas.WebState.Sim.HasPending) {
          pas.TsSim.SimChoose(pas.WebState.Sim,N);
          K = -1;
          for (var $l = rtl.length(pas.WebState.Sim.Log) - 1; $l >= 0; $l--) {
            I = $l;
            if (pas.WebState.Sim.Log[I].IsDecision) {
              K = I;
              break;
            };
          };
          if (K >= 0) {
            this.OpenModal(pas.WebViews.ModalOutcome(K),"outcome")}
           else this.CloseModal();
        };
      } else if (Act === "resume") {
        this.CloseModal();
        this.RefreshMission();
        if (pas.WebState.Sim.Phase === 5) this.FinishMission();
      };
    };
    this.EnterLab = function () {
      if (!(pas.WebState.HasDesign && (pas.WebState.D.Scenario === pas.WebState.Scen) && (pas.WebState.D.Difficulty === pas.WebState.Difficulty) && (pas.WebState.D.Sandbox === pas.WebState.Sandbox))) {
        pas.WebState.D.$assign(pas.TsEngine.NewDesign(pas.WebState.Scen,pas.WebState.Difficulty,pas.WebState.Sandbox));
        pas.WebState.HasDesign = false;
        pas.WebState.HasPrev = false;
        pas.WebState.Recalc();
        pas.WebState.HasPrev = false;
        pas.WebState.SharedNote = "";
        pas.WebState.LabTab = 0;
      };
      this.Go(3);
    };
    this.StartMission = function () {
      if (pas.WebState.A.Blockers > 0) return;
      if (!this.FKeepSeed) pas.WebState.D.Seed = pas.WebState.NewSeed();
      this.FKeepSeed = false;
      pas.TsSim.SimStart(pas.WebState.Sim,pas.WebState.D);
      pas.WebState.HasSim = true;
      pas.WebState.HasCard = false;
      this.FMissionDone = false;
      this.FLaunching = false;
      this.FRunning = true;
      this.FSpeed = 1;
      this.FAccum = 0;
      this.FShownLog = 0;
      this.CloseModal();
      this.Go(5);
    };
    this.StepSim = function () {
      var Was = 0;
      Was = pas.WebState.Sim.Phase;
      pas.TsSim.SimAdvance(pas.WebState.Sim);
      if (pas.WebState.Sim.HasPending) {
        this.RefreshMission();
        this.OpenModal(pas.WebViews.ModalDecision(),"decision");
        return;
      };
      if (Was === 1) {
        this.FLaunching = true;
        this.FLaunchT0 = pas.WebUtil.NowMs();
        this.FLaunchFail = pas.WebState.Sim.LostAtLaunch;
        this.FLaunchSize = 1;
        if (pas.WebState.D.Launcher >= 0) this.FLaunchSize = pas.TsCatalog.Launchers[pas.WebState.D.Launcher].Size;
        this.SetControls();
        pas.WebUtil.SetText("m-clock","Launch");
        return;
      };
      this.RefreshMission();
      if ((pas.WebState.Sim.Phase === 5) && !this.FMissionDone) this.FinishMission();
    };
    this.RefreshMission = function () {
      var Bar = null;
      var Box = null;
      var Ctx = null;
      var S = "";
      if (pas.WebState.Screen !== 5) return;
      pas.WebUtil.SetHtml("m-side",pas.WebViews.ViewMissionSide());
      if (!this.FLaunching) this.SyncLog();
      Bar = pas.WebUtil.El("m-prog");
      if (Bar !== null) Bar.style.setProperty("width",pas.TsFmt.FmtNum(pas.TsSim.SimProgress(pas.WebState.Sim) * 100,1) + "%");
      var $tmp = pas.WebState.Sim.Phase;
      if ($tmp === 0) {
        S = "Building the spacecraft"}
       else if ($tmp === 1) {
        S = "On the launch pad"}
       else if ($tmp === 2) {
        S = "Cruise: " + pas.TsFmt.FmtYears(pas.WebState.Sim.Week / 52) + " since launch"}
       else if ($tmp === 3) {
        S = "Arriving"}
       else if ($tmp === 4) {
        S = "Science week " + pas.SysUtils.IntToStr(pas.WebState.Sim.SciWeek) + " of " + pas.SysUtils.IntToStr(pas.WebState.Sim.PlanWeeks)}
       else {
        S = "Mission over";
      };
      pas.WebUtil.SetText("m-clock",S);
      if (rtl.length(pas.WebState.Sim.HistScience) > 1) {
        Box = pas.WebUtil.El("m-chartbox");
        if ((Box !== null) && Box.hidden) Box.hidden = false;
        if ((((rtl.length(pas.WebState.Sim.HistScience) % 3) === 0) || (pas.WebState.Sim.Phase === 5)) && pas.WebDraw.Prep("cv-chart",640,170,{get: function () {
            return Ctx;
          }, set: function (v) {
            Ctx = v;
          }})) pas.WebDraw.DrawChart(Ctx,640,170,pas.WebState.Sim);
      };
    };
    this.SyncLog = function () {
      var E = null;
      E = document.getElementById("m-log");
      if (E === null) return;
      while (this.FShownLog < rtl.length(pas.WebState.Sim.Log)) {
        E.insertAdjacentHTML("afterbegin",pas.WebViews.LogItemHtml(this.FShownLog));
        this.FShownLog += 1;
      };
    };
    this.SetControls = function () {
      pas.WebUtil.SetHtml("m-ctl",pas.WebViews.ViewMissionControls(this.FRunning,this.FMissionDone,this.FLaunching,this.FSpeed));
    };
    this.EndLaunch = function () {
      if (!this.FLaunching) return;
      this.FLaunching = false;
      this.SyncLog();
      this.RefreshMission();
      if (pas.WebState.Sim.Phase === 5) {
        this.FinishMission()}
       else this.SetControls();
    };
    this.FinishMission = function () {
      var E = pas.WebStore.TLogEntry.$new();
      if (this.FMissionDone) return;
      this.FMissionDone = true;
      this.FRunning = false;
      pas.WebState.Card.$assign(pas.TsScore.ScoreMission(pas.WebState.Sim));
      pas.WebState.HasCard = true;
      E.Date = pas.WebUtil.TodayIso();
      E.Scenario = pas.TsScenarios.Scenarios[pas.WebState.Scen].Id;
      E.ScenarioName = pas.TsScenarios.Scenarios[pas.WebState.Scen].Name;
      E.Grade = pas.WebState.Card.Grade;
      E.Outcome = pas.WebState.Card.Outcome;
      E.Crew = pas.WebState.CrewText();
      E.Code = pas.TsEngine.EncodeDesign(pas.WebState.D);
      E.Score = pas.WebState.Card.Total;
      E.Players = pas.WebState.Players;
      E.SciencePct = pas.WebState.Card.SciencePct;
      E.CostM = pas.WebState.Card.FinalCostM;
      E.CapM = pas.WebState.Card.CapM;
      pas.WebStore.AddLogEntry(E);
      this.SyncLog();
      this.SetControls();
      this.RefreshMission();
    };
    this.DataChanged = function () {
      if (pas.WebState.HasDesign) {
        pas.WebState.A.$assign(pas.TsEngine.Analyze(pas.WebState.D));
        pas.WebState.HasPrev = false;
      };
      if ((pas.WebState.Screen === 0) || (pas.WebState.Screen === 2)) {
        this.Render()}
       else if (pas.WebState.Screen === 3) this.RenderLab(true);
    };
    this.LoadFromHash = function () {
      var H = "";
      var P = 0;
      H = window.location.hash;
      P = pas.System.Pos("m=",H);
      if (P > 0) this.UseDesign(pas.System.Copy(H,P + 2,H.length),"A shared design was loaded. Fly it as it is to compare scores on equal terms, or try to improve it.");
    };
    this.UseDesign = function (Code, Note) {
      var E = pas.TsTypes.TDesign.$new();
      if (!pas.TsEngine.DecodeDesign(Code,E)) {
        pas.WebUtil.Toast("That design link could not be read.");
        return;
      };
      pas.WebState.D.$assign(E);
      pas.WebState.Scen = pas.WebState.D.Scenario;
      pas.WebState.Difficulty = pas.WebState.D.Difficulty;
      pas.WebState.Sandbox = pas.WebState.D.Sandbox;
      pas.WebState.HasDesign = false;
      pas.WebState.HasPrev = false;
      pas.WebState.Recalc();
      pas.WebState.HasPrev = false;
      pas.WebState.SharedNote = Note;
      this.FKeepSeed = true;
      pas.WebState.LabTab = 0;
      pas.WebState.Screen = 3;
    };
    this.ShareDesign = function () {
      var Base = "";
      var P = 0;
      Base = window.location.href;
      P = pas.System.Pos("#",Base);
      if (P > 0) Base = pas.System.Copy(Base,1,P - 1);
      this.FShareUrl = Base + "#m=" + pas.TsEngine.EncodeDesign(pas.WebState.D);
      this.OpenModal(pas.WebViews.ModalShare(this.FShareUrl),"info");
    };
    this.Start = function () {
      var I = 0;
      var S = "";
      this.FSpeed = 1;
      this.FModalKind = "";
      pas.WebDraw.LoadImages();
      pas.WebDraw.DrawStars();
      for (I = 0; I <= 3; I++) {
        S = pas.WebStore.LoadSetting("player" + pas.SysUtils.IntToStr(I),"");
        if (S !== "") pas.WebState.PlayerName[I] = S;
      };
      I = pas.SysUtils.StrToIntDef(pas.WebStore.LoadSetting("difficulty","1"),1);
      if ((I >= 0) && (I <= 2)) pas.WebState.Difficulty = I;
      document.addEventListener("click",rtl.createSafeCallback(this,"OnClick"));
      document.addEventListener("input",rtl.createSafeCallback(this,"OnInput"));
      document.addEventListener("change",rtl.createSafeCallback(this,"OnChange"));
      document.addEventListener("keydown",rtl.createSafeCallback(this,"OnKey"));
      window.addEventListener("resize",rtl.createSafeCallback(this,"OnResize"));
      pas.WebNasa.LoadNasaData(rtl.createCallback(this,"DataChanged"));
      this.LoadFromHash();
      this.Render();
      window.requestAnimationFrame(rtl.createCallback(this,"Frame"));
    };
  });
},["WebUtil","WebState","WebStore","WebNasa","WebDraw","WebViews","TsFmt","TsCatalog","TsScenarios","TsEngine","TsSim","TsScore","TsExamples"]);
rtl.module("program",["System","JS","Web","WebApp"],function () {
  "use strict";
  var $mod = this;
  this.Game = null;
  $mod.$main = function () {
    $mod.Game = pas.WebApp.TGame.$create("Create");
    $mod.Game.Start();
  };
});
