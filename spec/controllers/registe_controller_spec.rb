require 'rails_helper'
require "support/render_views"

describe RegisteController do
	fixtures :users
	fixtures :finance_waters

	let!(:set_session) do
		request.session[:admin]="admin"
	end

	describe "get index" do
		it "get index status" do
			get :index
			expect(response.status).to eq(200)
		end
		it "assigns index users" do
			get :index
			expect(assigns(:users)).to eq([users(:user_one)])
		end
		it "get index template" do
			get :index
			expect(response).to render_template("index")
		end

		context "get response.body" do
			it "get index say" do
				get :index
				expect(response.body).to match /用户ID/im
			end
		end
	end

	describe "post create" do
		it "no params" do
			post :create
			expect(response.status).to eq(400)
		end

		it "interface create" do
			userid=getUserId("001")
			expect {
				post :create,registe_params(userid)
			}.to change(User,:count).by(1)
			expect(response.body).to eq(ret_params_succ(userid).to_json)

			userid=getUserId("002")
			expect {
				post :create,registe_params(userid)
			}.to change(FinanceWater,:count).by(2)
			expect(response.body).to eq(ret_params_succ(userid).to_json)


			expect {
				post :create,registe_params(userid)
			}.to change{User.count}.by(0)
			expect(response.body).to eq(ret_params_fail(userid).to_json)
		end
	end

	describe "get show" do
		it "get show no system" do
			get :show,:userid=>'no_system',:format=>:json
			expect(response.status).to eq(400)


			get :show,:userid=>'no_system',:format=>:html
			expect(response).to redirect_to(registe_index_path)
			expect(flash[:notice]).to eq("system valid failure!")
		end

		it "get show user not exists" do
			get :show,:userid=>'not_exists_user',:system=>'mypost4u',:format=>:json
			expect(response.status).to eq(400)


			get :show,:userid=>'not_exists_user',:system=>'mypost4u',:format=>:html
			expect(response).to redirect_to(registe_index_path)
			expect(flash[:notice]).to eq("not_exists_user not exists in mypost4u !")
		end

		it "get show user succ" do
			get :show,:userid=>users(:user_one)['userid'],:system=>'mypost4u',:format=>:json
			expect(response.status).to eq(200)
			expect(response.body).to eq(User.find(users(:user_one)).to_json)
		end
	end

	def registe_params(userid)
		{
			'system'=>'mypost4u',
			'channel'=>'web',
			'userid'=>userid,
			'username'=>'testname',
			'email'=>'testname@126.com',
			'accountInitAmount'=>11.1,
			'accountInitReason'=>'init e_cash',
			'scoreInitAmount'=>22.2,
			'scoreInitReason'=>'init score',
			'operator'=>'system',
			'datetime'=>Time.now.strftime("%Y-%m-%d %H:%M:%S")
		}
	end

	def ret_params_succ(userid)
		water_no=[]
		User.find_by_userid(userid).finance_water.each do |f|
			water_no<<f.id.to_s
		end

		{
			'system'=>'mypost4u',
			'channel'=>'web',
			'userid'=>userid,
			'status'=>'success',
			'reasons'=>[],
			'water_no'=>water_no
		}
	end

	def ret_params_fail(userid)
		ret_hash={
			'system'=>'mypost4u',
			'channel'=>'web',
			'userid'=>userid,
			'status'=>'failure',
			'reasons'=>[],
			'water_no'=>[]
		}

		ret_hash['reasons']<<{'reason'=>"user has exists"}
		ret_hash['reasons']<<"create user failure"

		ret_hash
	end

	def getUserId(seq) 
		@time ||= Time.now.strftime("%Y%m%d%H%M%S")

		'SEPC_'+@time+'_'+seq
	end
end