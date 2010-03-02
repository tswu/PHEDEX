/**
 * This class creates a context-menu handler that interacts with a datatable or treeview and builds menus on-the-fly, depending on which element-type has been selected. The clickHandler routine is specific to the type of module that is being decorated (type=DataTable or type=TreeView) and is implemented separately, as a PHEDEX.DataTable.ContextMenu or a PHEDEX.TreeView.ContextMenu. See the documentation for those types for details.
 * @namespace PHEDEX.Component
 * @class ContextMenu
 * @constructor
 * @param sandbox {PHEDEX.Sandbox} reference to a PhEDEx sandbox object
 * @param args {object} reference to an object that specifies details of how the control should operate.
 */

/** The partner object. This is added by the core. The control should only use this to take the <strong>obj.id</strong> of the partner, so it can set up a listener for events from that specific partner.
 * @property args.payload.obj {PHEDEX.Module, or derivative thereof}
 */
/** Tell Tony to document this when he finds out what it does.
 * @property args.payload.typeMap {array}
 */
/** Configuration parameters for the YAHOO.widget.ContextMenu
 * @property args.payload.config {object}
 */
/** An array of names, used to lookup entries in PHEDEX.Registry that are added to the menu. For example, a 'links' entry would signify that the partner can provide enough information to create a PHEDEX.Module.LinkView module
 * @property typeNames {array}
 */
PHEDEX.namespace('Component');
PHEDEX.Component.ContextMenu=function(sandbox,args) {
  YAHOO.lang.augmentObject(this, new PHEDEX.Base.Object());

  var _me = 'component-contextmenu',
      _sbx = sandbox;

  var obj = args.payload.obj;
  if ( obj ) {
    try {
      YAHOO.lang.augmentObject(this,PHEDEX[obj.type].ContextMenu(obj,args),true);
    } catch(ex) {
      log('cannot augment object of type '+obj.type+' with a ContextMenu','warn',_me);
    }
  }

  _construct = function() {
    return {
        id: _me + '_' + PxU.Sequence(),

/**
 * Create the context-menu, storing it in <strong>this.menu</strong>
 * @method Create
 * @param config {object} configuration object, originally given to the constructor as <strong>args.payload.config</strong>
 * @return menu {YAHOO.widget.contextMenu}
 */
      Create: function(config) {
        var i = PHEDEX.Util.Sequence();
        if ( !config.lazyload ) { config.lazyload = true; }
        var menu = new YAHOO.widget.ContextMenu("contextmenu_"+i,config);
        menu.cfg.setProperty('zindex',10);
        return menu;
      },

/**
 * Initialise the control. Called internally. Initialises the type-map, creates the menu, adds the clickEvent handler, and listens for notifications to itself
 * @method _init
 * @private
 * @param args {object} the arguments passed into the contructor
 */
      _init: function(args) {
        var types = args.payload.types || [],
            obj  = args.payload.obj;

/**
 * Handle messages sent directly to this module. This function is subscribed to listen for its own <strong>id</strong> as an event, and will take action accordingly.
 * @method selfHandler
 * @param ev {string} name of the event that was sent to this module
 * @param arr {array} array of arguments for the given event
 * @private
 */
        this.selfHandler = function(o) {
          return function(ev,arr) {
            var action = arr[0],
                value = arr[1];
            log('selfHandler: ev='+ev+' args='+YAHOO.lang.dump(arr,1),'info',_me);
            switch (action) {
              case 'WidgetsByInputType': {
                o[action][value] = arr[2];
                break;
              }
              case 'InputTypes': {
                o[action] = value;
                break;
              }
              case 'extraContextTypes': {
                for (var type in value) {
                  _sbx.notify('Registry','getWidgetsByInputType',type,o.id);
                }
                break;
              }
            }
          }
        }(this);
        _sbx.listen(this.id,this.selfHandler);

        this.typeMap = args.payload.typeMap;
        this.typeNames = args.payload.typeNames;
        this.InputTypes = [];
        this.WidgetsByInputType = [];
        for (var type in this.typeNames) {
          _sbx.notify('Registry','getWidgetsByInputType',this.typeNames[type],this.id);
        }
        var config = args.payload.config || {};
        this.contextMenu = this.Create(config);
        var buildMe = function(o) {
          return function(p_sType, p_aArgs) {
            o.Build(this.contextEventTarget);
          }
        }(this);
        var hideMe = function(o) {
          return function() {
            if ( o.onContextMenuHide ) {
              o.onContextMenuHide(this.contextEventTarget);
            }
            this.clearContent();
          }
        }(this);
        this.contextMenu.beforeShowEvent.subscribe( buildMe );
        this.contextMenu.clickEvent.subscribe(this.onContextMenuClick, obj);
        this.contextMenu.hideEvent.subscribe( hideMe );
        _sbx.notify(obj.id,'getExtraContextTypes',this.id);
      },

/** reset the menu to empty. This is a trivial function, but it hides the internal contextmenu, which is good.
 * @method Clear
 */
      Clear: function() { this.contextMenu.clearContent(); },

/** build the menu and render it. Looks up two sources of information, the global registry, and the local info in the <strong>typeNames</strong>. The global registry knows about big things, like creating modules. <strong>typeNames</strong> knows all the rest, like column-sorting, field-hiding, and stuff like that. Called in response to a 'beforeShow' event on the context menu, to create the content just-in-time.
 * @method Build
 */
      Build: function(target) {
        var typeNames = [],
            name;
        for (var i in this.typeNames) { typeNames.push(this.typeNames[i]); } // need a deep copy to avoid overwriting this.typeNames!
        if ( this.onContextMenuBeforeShow ) {
          typeNames = this.onContextMenuBeforeShow(target, typeNames);
        }
        for (var i in typeNames)
        {
// N.B. Do this rather than just loop over this.WidgetsByInputType keys, in order to guarantee the ordering will be the same
// as the order of registration. Otherwise it's conceivable the menu-order would differ between runs or between browsers
          name = typeNames[i];
          var w = this.WidgetsByInputType[name];

//         First check the core widget registry to see if any widgets can be made
          for (var j in w)
          {
            var widget = w[j];
            if (widget.context_item) {
              log('Adding Widget name='+name+' label='+w[j].label, 'info', _me);
              var item = new YAHOO.widget.MenuItem(w[j].label);
//            Build a constructor function (fn) in the menu value object
              item.value = { 'widget': widget.widget,
                             'type': widget.type,
                             'fn':function(_w) {
                                return function(opts,el) {
                                  var arg = opts[this.type];
                                  log('Construct registered widget:'+
                                      ' widget='+this.widget+
                                      ' type='+this.type+
                                      ' arg='+arg,
                                      'info', _me);
                                  _sbx.notify('CreateModule',_w.short_name,opts);
                                };
                              }(widget)
                            };
                this.contextMenu.addItem(item);
                log('Build: '+name+' label:'+w[j].label,'info',_me);
            }
          }

//        Next check our own registry
          var list = PHEDEX.Component.ContextMenu.items[name];
          for (var j in list)
          {
            var item = new YAHOO.widget.MenuItem(list[j].label);
            item.value = { 'type':name,
                           'fn':list[j].callback };
            this.contextMenu.addItem(item);
            log('Build: '+name+' label:'+list[j].label,'info',_me);
          }
        }
        this.contextMenu.render();
      },
    };
  };
  YAHOO.lang.augmentObject(this,_construct(this),true);
  this._init(args);
  return this;
}

// some static methods/variables for adding 'global' menu-items
/** A list of arrays of {label,callback} pairs, used to define handlers for the named array-index. Used by PHEDEX.Component.ContextMenu.Add to maintain the set of possible menu-items for all cases.
 * @property items
 * @type object
 * @static
 */
PHEDEX.Component.ContextMenu.items={};
/**
 * Add an item for use in contextmenus.
 * @method Add
 * @static
 * @param name {string} name(-space) to add the handler to. E.g. 'datatable' for something common to all datatable modules
 * @param label {string} the text that will be used to label this entry in the context-menu
 * @param callback {function} the function that will be invoked when this menu-item is selected. Takes two arguments, <strong>opts</strong> is an object containing information about the specific data-element that was selected (i.e. in 'phedex data-space'), and <strong>el</strong> contains information about the YUI widget-element that was selected (DataTable, TreeView). See the specific PHEDEX.DataTable.ContextMenu and PHEDEX.TreeView.ContextMenu classes for details.
 */
PHEDEX.Component.ContextMenu.Add = function(name,label,callback) {
  var _items = PHEDEX.Component.ContextMenu.items;
  if ( !_items[name] ) { _items[name] = {}; }
  if ( _items[name][label] ) { return; }
  _items[name][label] = { label:label, callback:callback };
  log('Add: '+name+': #items:'+_items[name].length,'info','component-contextmenu');
};

log('loaded...','info','component-contextmenu');