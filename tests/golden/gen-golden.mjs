// Golden-vector generator: runs the *actual* DSP functions from the web gold
// master (app/index.html) and dumps fixtures the Rust core must reproduce.
//
// The functions below are copied verbatim from app/index.html (progress
// callbacks dropped). If the gold master's DSP ever changes, regenerate:
//   node tests/golden/gen-golden.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'fixtures', 'golden');

// ── constants (verbatim) ──
const FFT_SIZE = 4096, HOP_SIZE = 1024, SR = 44100, TOT_BINS = FFT_SIZE / 2 + 1;
const BEATS_PER_MEASURE = 4, BPM_MIN = 60, BPM_MAX = 240, BPM_FALLBACK = 120;
const BPM_PREFERRED_MIN = 80, BPM_PREFERRED_MAX = 180, TEMPO_MIN_CONFIDENCE = 0.04;

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

// ── FFT / STFT (verbatim) ──
function hann(N){const w=new Float32Array(N);for(let i=0;i<N;i++)w[i]=0.5-0.5*Math.cos(2*Math.PI*i/N);return w;}
function fftIP(re,im){
  const N=re.length;
  for(let i=1,j=0;i<N;i++){let bit=N>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){[re[i],re[j]]=[re[j],re[i]];[im[i],im[j]]=[im[j],im[i]];}}
  for(let len=2;len<=N;len<<=1){const a=-2*Math.PI/len,wr0=Math.cos(a),wi0=Math.sin(a);
    for(let i=0;i<N;i+=len){let wr=1,wi=0;for(let j=0;j<len>>1;j++){const u=i+j,v=u+(len>>1);
      const tRe=wr*re[v]-wi*im[v],tIm=wr*im[v]+wi*re[v];
      re[v]=re[u]-tRe;im[v]=im[u]-tIm;re[u]+=tRe;im[u]+=tIm;
      const nr=wr*wr0-wi*wi0;wi=wr*wi0+wi*wr0;wr=nr;}}}
}
function stft(sig,win){
  const F=Math.floor((sig.length-FFT_SIZE)/HOP_SIZE)+1;
  const re=[],im=[],fr=new Float32Array(FFT_SIZE),fi=new Float32Array(FFT_SIZE);
  for(let f=0;f<F;f++){const s=f*HOP_SIZE;
    for(let i=0;i<FFT_SIZE;i++){fr[i]=(s+i<sig.length?sig[s+i]:0)*win[i];fi[i]=0;}
    fftIP(fr,fi);
    re.push(new Float32Array(fr.subarray(0,TOT_BINS)));
    im.push(new Float32Array(fi.subarray(0,TOT_BINS)));
  }
  return {re,im,F};
}

// ── tempo (verbatim) ──
function chooseTempoCandidate(candidates){
  const sorted=candidates.filter(c=>Number.isFinite(c.score)&&Number.isFinite(c.bpm)&&c.lag>0).sort((a,b)=>b.score-a.score);
  const best=sorted[0];
  if(!best)return {bpm:BPM_FALLBACK,rawBpm:BPM_FALLBACK,score:0,lag:0};
  const preferred=sorted.find(c=>c.bpm>=BPM_PREFERRED_MIN&&c.bpm<=BPM_PREFERRED_MAX&&c.score>=best.score*0.85);
  if((best.bpm<BPM_PREFERRED_MIN||best.bpm>BPM_PREFERRED_MAX)&&preferred)return preferred;
  return best;
}
function tempoFallback(){return {bpm:BPM_FALLBACK,confidence:0,beatOffset:0,measureOffset:0,offset:0,downbeatConfidence:0};}
function onsetScoreAt(onset,frames,offset,stride){
  let score=0,count=0;
  for(let i=offset;i<frames;i+=stride){score+=onset[i]||0;if(i>0)score+=(onset[i-1]||0)*0.5;if(i+1<frames)score+=(onset[i+1]||0)*0.5;count++;}
  return count?score/count:0;
}
function estimateMeasureOffset(onset,frames,beatLag,beatOffsetFrame,hopSec){
  const beatOffset=beatOffsetFrame*hopSec, measureLag=beatLag*BEATS_PER_MEASURE;
  if(measureLag>=frames)return {offset:beatOffset,confidence:0};
  const phases=[];
  for(let phase=0;phase<BEATS_PER_MEASURE;phase++){const offsetFrame=beatOffsetFrame+(phase*beatLag);phases.push({offset:offsetFrame*hopSec,score:onsetScoreAt(onset,frames,offsetFrame,measureLag)});}
  phases.sort((a,b)=>b.score-a.score);
  const best=phases[0], second=phases[1]||{score:0};
  const total=phases.reduce((s,p)=>s+p.score,0);
  const share=best&&total>0?best.score/total:0;
  const confidence=best&&best.score>0?(best.score-second.score)/best.score:0;
  if(best&&confidence>=0.12&&share>=0.36)return {offset:best.offset,confidence};
  return {offset:beatOffset,confidence};
}
function estimateTempo(signal,sampleRate){
  if(!signal||!signal.length||!sampleRate||sampleRate<=0)return tempoFallback();
  const minSamples=sampleRate*5; if(signal.length<minSamples)return tempoFallback();
  const frame=Math.max(1,Math.floor(sampleRate*0.03)), hop=Math.max(1,Math.floor(sampleRate*0.01));
  const frames=Math.floor((signal.length-frame)/hop); if(frames<8)return tempoFallback();
  const onset=new Float32Array(frames); let sm=0,prevSm=0,total=0;
  for(let i=0;i<frames;i++){let rms=0;const base=i*hop;for(let j=0;j<frame;j++){const sample=signal[base+j]||0;rms+=sample*sample;}rms=Math.sqrt(rms/frame);sm=sm*0.84+rms*0.16;const v=sm-prevSm;onset[i]=v>0?v:0;prevSm=sm;total+=onset[i];}
  if(total===0)return tempoFallback();
  let mean=0;for(let i=0;i<frames;i++)mean+=onset[i];mean/=frames;
  let energy=0;for(let i=0;i<frames;i++){const d=onset[i]-mean;energy+=d*d;}if(energy<1e-10)return tempoFallback();
  const hopSec=hop/sampleRate;
  const minLag=Math.max(1,Math.round((60/BPM_MAX)/hopSec)), maxLag=Math.max(minLag+1,Math.floor((60/BPM_MIN)/hopSec));
  const capLag=Math.min(maxLag,frames-2); if(minLag>=capLag)return tempoFallback();
  let bestLag=-1,bestScore=-Infinity;const candidates=[];
  for(let lag=minLag;lag<=capLag;lag++){let cross=0,a2=0,b2=0;for(let i=lag;i<frames;i++){const a=onset[i]-mean,b=onset[i-lag]-mean;cross+=a*b;a2+=a*a;b2+=b*b;}const score=cross/Math.sqrt((a2*b2)+1e-12);let bpm=60/(lag*hopSec);while(bpm<BPM_MIN)bpm*=2;while(bpm>BPM_MAX)bpm/=2;candidates.push({lag,rawBpm:60/(lag*hopSec),bpm,score});if(score>bestScore){bestScore=score;bestLag=lag;}}
  if(!Number.isFinite(bestScore)||!Number.isFinite(bestLag)||bestLag<=0||bestScore<TEMPO_MIN_CONFIDENCE)return tempoFallback();
  const selected=chooseTempoCandidate(candidates);
  let bestOffset=0,bestOffsetScore=-Infinity;
  for(let o=0;o<selected.lag;o++){let score=0;for(let i=o;i<frames;i+=selected.lag)score+=onset[i];if(score>bestOffsetScore){bestOffsetScore=score;bestOffset=o;}}
  const beatOffset=bestOffset*hopSec;
  const measureOffset=estimateMeasureOffset(onset,frames,selected.lag,bestOffset,hopSec);
  return {bpm:clamp(selected.bpm,BPM_MIN,BPM_MAX),confidence:selected.score,beatOffset,measureOffset:measureOffset.offset,offset:measureOffset.offset,downbeatConfidence:measureOffset.confidence};
}

// ── loop math (verbatim, parameterized on a small state) ──
function makeLoopState(bpm, measureOffset, beatOffset, duration){
  const measureLength=()=>(60/clamp(bpm,BPM_MIN,BPM_MAX))*BEATS_PER_MEASURE;
  function snapLoopEnd(currentSec,loopLength=measureLength()){
    const measure=measureLength();
    if(!measure||!Number.isFinite(currentSec)||!duration)return 0;
    const activeLength=Number.isFinite(loopLength)&&loopLength>0?loopLength:measure;
    const grid=Math.min(measure,activeLength);
    const offset=clamp(Number.isFinite(measureOffset)?measureOffset:(beatOffset||0),0,Math.max(0,measure-1e-6));
    const boundary=offset+Math.floor((currentSec-offset)/grid)*grid;
    const nextBoundary=boundary+grid;
    const epsilon=Math.min(0.03,grid*0.25);
    if(boundary>=0&&Math.abs(currentSec-boundary)<=epsilon)return boundary;
    return Math.max(0,nextBoundary);
  }
  function loopRangeFor(currentSec,loopLength=measureLength()){
    const length=Number.isFinite(loopLength)&&loopLength>0?loopLength:measureLength();
    let end=snapLoopEnd(currentSec,length); let start=end-length;
    if(start<0){start=0;end=length;}
    return {start,end};
  }
  return {measureLength,snapLoopEnd,loopRangeFor};
}

// ── deterministic shared signals (mirrored exactly in the Rust test) ──
// Short signal for exact spectral parity (dumped so Rust uses identical input).
function shortSignal(n){
  const s=new Float32Array(n);
  for(let i=0;i<n;i++){const t=i/SR;s[i]=Math.sin(2*Math.PI*220*t)*0.3+Math.sin(2*Math.PI*440*t)*0.18+Math.sin(2*Math.PI*110*t)*0.12;}
  return s;
}
// Long signal (≥5s) for tempo; single expression per sample so f64→f32 rounding
// matches Rust bit-for-bit without dumping ~3MB of input.
function longSignal(n){
  const s=new Float32Array(n); const period=Math.round(0.5*SR); // 120 BPM
  for(let i=0;i<n;i++){
    const t=i/SR, phase=i%period;
    const click=phase<300?(1-phase/300)*0.5:0;
    s[i]=Math.sin(2*Math.PI*220*t)*0.25+click;
  }
  return s;
}

// ── generate ──
mkdirSync(OUT,{recursive:true});
const win=hann(FFT_SIZE);

const short=shortSignal(30000);
const st=stft(short,win);
const pickFrames=[0,5,15];
const stftFixture=pickFrames.map(f=>({
  frame:f,
  bins:Array.from({length:64},(_,b)=>({b,re:st.re[f][b],im:st.im[f][b]})),
}));

const long=longSignal(Math.round(6*SR));
const tempo=estimateTempo(long,SR);

const loop=makeLoopState(120,0,0,60);
const loopCases=[
  {currentSec:2.6,loopLength:2.0},
  {currentSec:1.2,loopLength:0.5},
  {currentSec:4.01,loopLength:2.0},
  {currentSec:1.0,loopLength:2.0},
].map(c=>({...c,end:loop.snapLoopEnd(c.currentSec,c.loopLength),range:loop.loopRangeFor(c.currentSec,c.loopLength)}));

const fixture={
  meta:{FFT_SIZE,HOP_SIZE,SR,TOT_BINS,source:'app/index.html'},
  shortSignal:Array.from(short),
  hannSamples:{n:FFT_SIZE,values:[win[1],win[1024],win[2048],win[3072]]},
  stft:stftFixture,
  tempo:{n:long.length,bpm:tempo.bpm,confidence:tempo.confidence,beatOffset:tempo.beatOffset,measureOffset:tempo.measureOffset},
  loops:loopCases,
};

writeFileSync(join(OUT,'dsp-golden.json'),JSON.stringify(fixture));
console.log(`Wrote fixtures/golden/dsp-golden.json (${stftFixture.length} stft frames, tempo bpm=${tempo.bpm.toFixed(2)}, ${loopCases.length} loop cases)`);
