YtP = YAHOO.tool.Profiler;

PHEDEX.Profiler = function() {
  var number = YAHOO.widget.DataTable.formatNumber,
      _interval = 10000,
      _profile,
      el = document.getElementById('phedex-profiler'),
      _column,
      _columns = [
        {key:'Method', sortable:true, resizeable:true},
        {key:'Calls',   formatter:number, sortable:true, resizeable:true},
        {key:'Total',   formatter:number, sortable:true, resizeable:true},
        {key:'Average', formatter:number, sortable:true, resizeable:true},
        {key:'Max',     formatter:number, sortable:true, resizeable:true},
        {key:'Min',     formatter:number, sortable:true, resizeable:true},
        {key:'Median',  formatter:number, sortable:true, resizeable:true}
       ],
      _dataSource,
      _dataTable,
      _callback;

  if ( !el ) { return; }

  _profile = function() {
    var report = YtP.getFullReport(),
        _t = [], _table = [],
        i, j,
        tot, gTot = 0,
        median, p=[];
    for (i in report) {
      if ( report[i].calls > 0 ) {
        tot = 0;
        for (j in report[i].points) { tot += report[i].points[j]; }
        p = report[i].points.sort(function(a,b) { return a-b; });
        j = p.length;
        if ( j == 1 ) { median = p[0]; }
        else {
          if ( j%2 ) { median = p[(j-1)/2]; }
          else       { median = (p[j/2]+p[j/2-1])/2; } // average the two values around the putative median-point
        }
        gTot += tot;
        if ( tot ) {
          _t.push(
            [
              i,
              report[i].calls,
              tot,
              report[i].avg,
              report[i].max,
              report[i].min,
              median
            ]);
        }
      }
    }
    for (i in _t) {
      if ( _t[i][2]/gTot > 0.01 ) { //[2] matches the position of [tot] above. The comparison threshold is an arbitrary cut to keep the amount of on-screen data small
        _table.push(_t[i]);
      }
    }
    log(YAHOO.lang.dump(report),'debug','profile');
    return _table;
  };

  _dataSource = new YAHOO.util.DataSource(_profile),
  _dataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
  _dataSource.responseSchema = {
    fields: ['Method','Calls','Total','Average','Max','Min','Median']
  };
  _dataTable = new YAHOO.widget.DataTable(el, _columns, _dataSource);
  _column = _dataTable.getColumn('Total');
  _dataTable.sortColumn(_column,'yui-dt-desc');
  _callback = {
    success: function(sRequest,oResponse,oPayload) {
      var sort = this.getState().sortedBy || {},
          column;
      if ( sort.key ) { column = this.getColumn(sort.key); }
      this.onDataReturnInitializeTable(sRequest,oResponse,oPayload);
      if ( column ) { this.sortColumn(column,sort.dir); }
    },
    failure: function() {
      YAHOO.log("Polling failure", "error");
    },
    scope: _dataTable
  }
  setTimeout( function() {
      _dataSource.setInterval(_interval, null, _callback)
    }, _interval);
}();
