( //start with server setup
Server.default.options.numInputBusChannels_(0); //no input devices needed
s.reboot; //reboot server for new server options to take effect

s.waitForBoot({ //wait for server to reboot before executing the rest of our code
	x = TriSin.new; //initializing synth

	x.setParam('all',\attack,64); //these synth params won't change during the piece
	x.setParam('all',\release,21600);
	x.setParam('all',\cutoff_env,0);

	m = 8; //number of synth voices
	n = 3; //number of lfos per synth voice
	o = Array.series(m*n); //arithmetic series array of size equal to the total number of lfos
	p = PatternProxy(Pseq(o, inf)).asStream; //pattern derived from the arithmetic series array created above
	f = [174,285,396,417,528,639,741,852]; //solfeggio frequencies

	d = Dictionary.new;
	d.add(\l -> //samples folder
		PathName(thisProcess.nowExecutingPath.dirname++"/samples/PBP_woods/").entries.collect({
			arg sf;
			Buffer.readChannel(s, sf.fullPath, channels:[0]); //specify mono or stereo here with the channels argument
		});
	);

	Task({ //sampler definition
		SynthDef(\PlayBufPlayer, {
			arg out=0,
			bufnum=0,
			rate=1,
			start=0,
			end=1,
			t_trig=0,
			loops=1,
			amp=0.2,
			pan=0,
			rateSlew=0.1,
			panSlew=1,
			bus=0;
			var snd,
			snd2,
			pos,
			pos2,
			frames,
			duration,
			env,
			sig,
			startA,
			endA,
			startB,
			endB,
			crossfade,
			aOrB;
			aOrB=ToggleFF.kr(t_trig);
			startA=Latch.kr(start,aOrB);
			endA=Latch.kr(end,aOrB);
			startB=Latch.kr(start,1-aOrB);
			endB=Latch.kr(end,1-aOrB);
			crossfade=Lag.ar(K2A.ar(aOrB),0.1);
			rate=Lag.kr(rate,rateSlew)*BufRateScale.kr(bufnum);
			frames=BufFrames.kr(bufnum);
			duration=frames*(end-start)/rate.abs/s.sampleRate*loops;
			env=EnvGen.ar(
				Env.new(
					levels: [0,amp,amp,0],
					times: [0,duration-0.1,0.1],
				),
				gate:t_trig,
			);
			pos=Phasor.ar(
				trig:aOrB,
				rate:rate,
				start:(((rate>0)*startA)+((rate<0)*endA))*frames,
				end:(((rate>0)*endA)+((rate<0)*startA))*frames,
				resetPos:(((rate>0)*startA)+((rate<0)*endA))*frames,
			);
			snd=BufRd.ar(
				numChannels:1, //numChannels should be 1 for mono or 2 for stereo
				bufnum:bufnum,
				phase:pos,
				interpolation:4,
			);
			pos2=Phasor.ar(
				trig:(1-aOrB),
				rate:rate,
				start:(((rate>0)*startB)+((rate<0)*endB))*frames,
				end:(((rate>0)*endB)+((rate<0)*startB))*frames,
				resetPos:(((rate>0)*startB)+((rate<0)*endB))*frames,
			);
			snd2=BufRd.ar(
				numChannels:1, //numChannels should be 1 for mono or 2 for stereo
				bufnum:bufnum,
				phase:pos2,
				interpolation:4,
			);
			sig=Pan2.ar(
				MoogFF.ar(
					in:(crossfade*snd)+((1-crossfade)*snd2)*env,
					freq:\cutoff.kr(12000),
					gain:\resonance.kr(1)),
				pan
			);
			Out.ar(bus,sig)
		}).play(s,[\out,0]);
		s.sync;
		y = Array.fill(d[\l].size, {arg i; //initializing samplers and assigning params to lfos
			Synth(\PlayBufPlayer,[\bufnum,d[\l][i],\cutoff,t[i],\resonance,u[i],\pan,v[i],\amp,z[i]]);
		});
		s.sync;
	}).play;

	Task({
		32.yield; //give the synths some time to fade in
		Tdef( //sample sequencer with lots of randomization
			\y_player, {
				var delta, start, end, loops;
				loop {
					s.sync;
					delta = [0.125,0.25,0.5,1,2,4].wchoose([0.025,0.1,0.1,0.2,0.3,0.275]);
					start = rrand(0,0.99);
					end = start + rrand(0.0001,0.01);
					loops = [1,2,3,4,5,6].wchoose([0.5,0.2,0.1,0.1,0.05,0.05]);
					y[rrand(0,y.size-1)].set(\t_trig,1,\start,start,\end,end,\loops,loops);
					delta.yield
				}
			}
		).play;
	}).play;

	Task({
		32.yield; //give the synths some time to fade in
		Tdef( //separate sequencer for sampler playback rates
			\y_rates, {
				var delta, rate;
				loop {
					s.sync;
					delta = [0.125,0.25,0.5,1].wchoose([0.4,0.3,0.2,0.1]);
					rate = [0.25,0.5,1,1.5,2,3,4].wchoose([0.15,0.25,0.25,0.25,0.1,0.075,0.025])*[-1,1].wchoose([0.4,0.6]);
					y[rrand(0,y.size-1)].set(\rate,rate);
					delta.yield
				}
			}
		).play;
	}).play;

	l = Array.fill(m,{ //index, mRatio, and cutoff lfos
		arg j;
		Array.fill(n,{
			arg i;
			Ndef(
				p.next.asSymbol,
				{
					if(
						i == 0,
						LFDNoise1.kr(1/rrand(2,1024)).range(-3,3)
					);
					if(
						i == 1,
						LFDNoise1.kr(1/rrand(2,1024)).range(-1,24)
					);
					if(
						i == 2,
						LFDNoise1.kr(1/rrand(2,1024)).range(200,2400)
					);
				}
			)
		})
	});

	q = Array.fill(m,{ //pan lfos
		arg i;
		Ndef(
			(o.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(-1,1)
			}
		)
	});

	r = Array.fill(m,{ //resonance lfos
		arg i;
		Ndef(
			(o.size+q.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(0.25,3.0)
			}
		)
	});

	t = Array.fill(d[\l].size,{ //sampler cutoff lfos
		arg i;
		Ndef(
			(o.size+q.size+r.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(200,2400)
			}
		)
	});

	u = Array.fill(d[\l].size,{ //sampler resonance lfos
		arg i;
		Ndef(
			(o.size+q.size+r.size+t.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(0.25,3.0)
			}
		)
	});

	v = Array.fill(d[\l].size,{ //sampler pan lfos
		arg i;
		Ndef(
			(o.size+q.size+r.size+t.size+u.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(-1,1)
			}
		)
	});

	w = Array.fill(m,{ //synth amp lfos
		arg i;
		Ndef(
			(o.size+q.size+r.size+t.size+u.size+v.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(0,i.linlin(0,7,0.1,0.05)) //lower max volume for higher frequencies
			}
		)
	});

	z = Array.fill(d[\l].size,{ //sampler amp lfos
		arg i;
		Ndef(
			(o.size+q.size+r.size+t.size+u.size+v.size+w.size+i).asSymbol,
			{
				LFDNoise1.kr(1/rrand(2,1024)).range(0,0.9)
			}
		)
	});

	m.do({
		arg i; //assigning synth params to lfos
		x.setParam((i+1).asSymbol,\index,l[i][0]);
		x.setParam((i+1).asSymbol,\mRatio,l[i][1]);
		x.setParam((i+1).asSymbol,\cutoff,l[i][2]);
		x.setParam((i+1).asSymbol,\pan,q[i]);
		x.setParam((i+1).asSymbol,\resonance,r[i]);
		x.setParam((i+1).asSymbol,\amp,w[i]);
		x.trigger((i+1).asSymbol,f[i]/2); //dividing frequencies by two for vibes purposes
	});
}).play
)
