'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';

var callGetUnixtime = rpc.declare({ object: 'luci', method: 'getUnixtime', expect: { result: 0 } });
var callLuciVersion = rpc.declare({ object: 'luci', method: 'getVersion' });
var callSystemBoard = rpc.declare({ object: 'system', method: 'board' });
var callSystemInfo = rpc.declare({ object: 'system', method: 'info' });

var CPUINFO = '/proc/cpuinfo';
var CUR_FREQ = '/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq';
var TEMP = '/sys/class/thermal/thermal_zone0/temp';

// "ARMv8 Processor rev 4 (v8l) x 4 ( 900MHz 64.5°C )" - the vendor image
// shows frequency and temperature inline, so keep the same shape here.
function formatArchitecture(boardinfo, cpuinfo, freq, temp) {
	var arch = boardinfo.system || '';
	var match = (cpuinfo || '').match(/^\s*model name\s*:\s*(.+)$/m);

	if (match)
		arch = match[1].trim();

	var cpus = (cpuinfo || '').match(/^\s*processor\s*:/mg);
	if (cpus && cpus.length)
		arch += ' x ' + cpus.length;

	var extra = [];
	var mhz = parseInt(freq, 10);
	if (mhz > 0)
		extra.push(Math.round(mhz / 1000) + 'MHz');
	var celsius = parseInt(temp, 10);
	if (celsius > 0)
		extra.push((celsius / 1000).toFixed(1) + '\u00b0C');
	if (extra.length)
		arch += ' ( ' + extra.join(' ') + ' )';

	return arch;
}

return baseclass.extend({
	title: _('System'),
	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callLuciVersion(), { revision: _('unknown version'), branch: 'LuCI' }),
			L.resolveDefault(callGetUnixtime(), 0),
			uci.load('system'),
			L.resolveDefault(fs.read(CPUINFO), ''),
			L.resolveDefault(fs.read(CUR_FREQ), ''),
			L.resolveDefault(fs.read(TEMP), '')
		]);
	},
	render: function(data) {
		var boardinfo = data[0],
		    systeminfo = data[1],
		    luciversion = data[2],
		    unixtime = data[3],
		    cpuinfo = data[5],
		    freq = data[6],
		    temp = data[7];

		luciversion = luciversion.branch + ' ' + luciversion.revision;

		var datestr = null;
		if (unixtime) {
			var date = new Date(unixtime * 1000),
			    zn = uci.get('system', '@system[0]', 'zonename')?.replaceAll(' ', '_') || 'UTC',
			    ts = uci.get('system', '@system[0]', 'clock_timestyle') || 0,
			    hc = uci.get('system', '@system[0]', 'clock_hourcycle') || 0;
			datestr = new Intl.DateTimeFormat(undefined, {
				dateStyle: 'medium',
				timeStyle: (ts == 0) ? 'long' : 'full',
				hourCycle: (hc == 0) ? undefined : hc,
				timeZone: zn
			}).format(date);
		}

		var fields = [
			_('Hostname'), boardinfo.hostname,
			_('Model'), boardinfo.model,
			_('Architecture'), formatArchitecture(boardinfo, cpuinfo, freq, temp),
			_('Target Platform'), (L.isObject(boardinfo.release) ? boardinfo.release.target : ''),
			_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),
			_('Kernel Version'), boardinfo.kernel,
			_('Local Time'), datestr,
			_('Uptime'), systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'), Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(systeminfo.load[0] / 65535.0, systeminfo.load[1] / 65535.0, systeminfo.load[2] / 65535.0) : null
		];

		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [fields[i]]),
				E('td', { 'class': 'td left' }, [(fields[i + 1] != null) ? fields[i + 1] : '?'])
			]));
		}
		return table;
	}
});
