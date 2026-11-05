'use strict';
'require view';
'require fs';
'require poll';

function mhz(khz) {
	return (Number(khz) / 1000).toFixed(0) + ' MHz';
}

function celsius(milli) {
	return (Number(milli) / 1000).toFixed(1) + ' °C';
}

return view.extend({
	load: function() {
		return fs.exec('/usr/bin/sysinfo-json').then(function(res) {
			return JSON.parse(res.stdout || '{}');
		}).catch(function() {
			return {};
		});
	},

	render: function(info) {
		const table = E('table', { 'class': 'table' });
		const rows = [];

		rows.push([ _('Architecture'), info.arch || '—' ]);
		if (info.model)
			rows.push([ _('CPU model'), info.model ]);
		if (info.board)
			rows.push([ _('Board'), info.board ]);
		rows.push([ _('CPU cores'), String(info.cores || '—') ]);

		if (info.governor)
			rows.push([ _('Governor'), info.governor ]);
		if (info.freq_min && info.freq_max)
			rows.push([ _('Frequency range'),
				mhz(info.freq_min) + ' – ' + mhz(info.freq_max) ]);
		if (info.freq_avail)
			rows.push([ _('Available frequencies'),
				String(info.freq_avail).trim().split(/\s+/).map(mhz).join(', ') ]);

		(Array.isArray(info.cores_freq) ? info.cores_freq : []).forEach(function(c) {
			rows.push([ _('CPU %d frequency').format(c.cpu), mhz(c.khz) ]);
		});

		(Array.isArray(info.thermal) ? info.thermal : []).forEach(function(t) {
			rows.push([ _('Temperature (%s)').format(t.type || _('sensor')), celsius(t.milli_c) ]);
		});

		rows.forEach(function(r) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, r[0]),
				E('td', { 'class': 'td left', 'data-sysinfo': r[0] }, r[1])
			]));
		});

		const view_ = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('System')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Architecture, CPU frequency and temperature reported by the running kernel.')),
				table
			])
		]);

		poll.add(function() {
			return fs.exec('/usr/bin/sysinfo-json').then(function(res) {
				const fresh = JSON.parse(res.stdout || '{}');
				const cur = {};
				(Array.isArray(fresh.cores_freq) ? fresh.cores_freq : []).forEach(function(c) {
					cur[ _('CPU %d frequency').format(c.cpu) ] = mhz(c.khz);
				});
				(Array.isArray(fresh.thermal) ? fresh.thermal : []).forEach(function(t) {
					cur[ _('Temperature (%s)').format(t.type || _('sensor')) ] = celsius(t.milli_c);
				});
				view_.querySelectorAll('[data-sysinfo]').forEach(function(el) {
					const v = cur[el.getAttribute('data-sysinfo')];
					if (v)
						el.textContent = v;
				});
			}).catch(function() {});
		}, 5);

		return view_;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
