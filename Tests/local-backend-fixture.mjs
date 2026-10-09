import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [app,dir]=process.argv.slice(2);
const moduleAt=file=>import(pathToFileURL(path.join(app,file)));
const {createApp}=await moduleAt('server/index.mjs');
const {openAccounts}=await moduleAt('server/accounts.mjs');
const {desktopAccess}=await moduleAt('server/desktop.mjs');
const {emptyState}=await moduleAt('src/storage.js');
const {savedPlan}=await moduleAt('server/saved-plan.mjs');
const {mockClerk}=await moduleAt('tests/helpers/clerk.mjs');
const clerk=mockClerk(),identity=clerk.add('nativefixture');
const server=await createApp({dataDir:dir,identityService:clerk});
const accounts=await openAccounts(dir),user=accounts.bootstrapOwner(identity.identity);
const state=emptyState();
state.assignments=[{id:'a',title:'Synthetic work',course:'TEST',kind:'assignment',deadline:'2026-12-01',dueTime:'23:59'}];
state.tasks=[{id:'first',assignmentId:'a',title:'Synthetic task',date:'2026-10-09',minutes:30,order:0,completedAt:null},
  {id:'second',assignmentId:'a',title:'Remaining study step',date:'2026-10-09',minutes:15,order:1,completedAt:null}];
accounts.save(user,savedPlan(state),0);
const {token}=desktopAccess(accounts).create(user,{label:'Native integration probe',expiresInDays:7});
server.listen(0,'127.0.0.1',()=>{
  // Credential IPC to the parent process, which pipes it directly to the probe's stdin.
  // This stream is never shown, logged, written to disk, or used for personal credentials.
  process.stdout.write(JSON.stringify({token,port:server.address().port})+'\n');
});
process.on('SIGTERM',()=>{server.close(()=>{accounts.close();process.exit(0);});});
